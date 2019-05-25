#!/usr/bin/perl

use strict;
use warnings;

use Text::CSV;
use Date::Parse;
use Time::HiRes;
use POSIX qw(strftime);
use List::Util qw(sum sum0);


my $input_file = shift || die "ERROR: Input filename required.\n";
my $mapping_file = shift || die "ERROR: Mapping filename required.\n";

# Load the mappings file and parse it/pre-compile regexes, etc.
my @account_mappings = ();
my $credit_mappings = {};
my $debit_mappings = {};
open my $mfh, "<:encoding(utf8)", $mapping_file or die "ERROR: $mapping_file: $!\n";
MAPPING: while(<$mfh>) {
    chomp;
    if(/^account\s+\/(.*)\/\s+([^\s,#\/]+)\s*(?:#.*)?$/) {
        # Account mapping
        push @account_mappings, {account=>$2, hits=>0, re=>qr/$1/};
#        print "Account mapping: [$1] -> [$2]\n";
    } elsif(/^(credit|debit)\s+([^\s,#\/]+)\s+\/(.*)\/\s+([^#\/]*)\s*(?:#.*)?$/) {
        # Credit/debit mapping
        my ($type, $account, $prere, @taglist) = ($1, $2, $3, (split /,/, $4));
        my $re = qr/$prere/;
        foreach(@taglist) {
            s/^\s*(.*?)\s*$/$1/;
        }
        my $mappings = ($type eq "credit") ? $credit_mappings : $debit_mappings;
        $mappings->{$account} = [] if !defined $mappings->{$account};
        push @{$mappings->{$account}}, {re=>$re, prere=>$prere, hits=>0, tags=>\@taglist};
#        print "$type mapping: [$account] [$prere] -> [".(join(";",@taglist))."]\n";
    } elsif(/^\s*(?:#.*)?$/) {
        # ignore empty or comment lines
    } elsif(/^__END__$/) {
        # Terminate early and ignore subsequent mappings
        last MAPPING;
    } else {
        # Don't understand this line! complain!
        die "ERROR: Mapping file [$mapping_file:$.] syntax error: [$_]\n";
    }
}
close $mfh;

print "Loaded ".(scalar @account_mappings)." account mappings.\n";
print "Loaded ".(sum0 map {scalar @{$credit_mappings->{$_}}} keys %{$credit_mappings})." credit mappings.\n";
print "Loaded ".(sum0 map {scalar @{$debit_mappings->{$_}}} keys %{$debit_mappings})." debit mappings.\n";



# Load in the transactions... eventually should probably not just slurp this all in one go...
my $csv=Text::CSV->new({binary=>1});
open my $fh, "<:encoding(utf8)",$input_file or die "ERROR: $input_file: $!\n";

$csv->column_names("date","mint_desc","desc","amount","type","mint_cat","account","mint_labels","mint_notes");
my $rows=$csv->getline_hr_all($fh,1);
$csv->eof or $csv->error_diag();
close $fh;


my %account_cache = ();
my @double_hit_account_events = ();
sub determine_account {
    my ($account) = @_;

    if(!defined $account_cache{$account}) {
        my @account_hits = ();
        foreach(@account_mappings) {
            if($account =~ $_->{re}) {
                push @account_hits, $_->{account};
                $account_cache{$account} = $_->{account};
                ++$_->{hits};
            }
        }

        if(scalar @account_hits > 1) {
            push @double_hit_account_events, {in=>$account, matches=>\@account_hits};
            print "WARNING: Double account hit: [$account] => (".(join(",", @account_hits)).")\n";
        }
    }

    return $account_cache{$account}
}

my %tag_cache = ();
my @double_hit_tag_events = ();
sub determine_tags {
    my ($account, $type, $desc) = @_;

    return undef if !defined $account || !defined $type;

    $tag_cache{$type} = {} if !defined $tag_cache{$type};
    $tag_cache{$type}->{$account} = {} if !defined $tag_cache{$type}->{$account};

    if(!defined $tag_cache{$type}->{$account}->{$desc}) {
        my @tag_hits = ();
        my $mappings = ($type eq "credit") ? $credit_mappings : $debit_mappings;

        foreach(@{$mappings->{$account}}, @{$mappings->{"*"}}) {
            if($desc =~ $_->{re}) {
#                print "Matched [$type] [$account] [$desc] on [$_->{prere}]\n";
                push @tag_hits, $_->{tags};
                $tag_cache{$type}->{$account}->{$desc} = [] if !defined $tag_cache{$type}->{$account}->{$desc};
                push @{$tag_cache{$type}->{$account}->{$desc}}, @{$_->{tags}};
                ++$_->{hits};
            } else {
#                print "Unmatched [$type] [$account] [$desc] on [$_->{prere}]\n";
            }
        }

        if(scalar @tag_hits > 1) {
            push @double_hit_tag_events, {in=>$desc, account=>$account, type=>$type, matches=>\@tag_hits};
            print "WARNING: Double desc hit: [$type] [$account] [$desc] => (".(join(";", map { join(",", @{$_}) } @tag_hits)).")\n";
       }
    }

    return $tag_cache{$type}->{$account}->{$desc};
}





my %accounts_not_found = ();
my %desc_not_found = ();
my $account_nonhits = 0;
my $total_transactions = 0;
my $total_credits = 0;
my $total_debits = 0;
my $desc_nonhits = 0;
my $credit_nonhits = 0;
my $debit_nonhits = 0;
my $unique_credit_nonhits = 0;
my $unique_debit_nonhits = 0;
foreach(@{$rows}) {
    ++$total_transactions;
    ++$total_credits if $_->{type} eq "credit";
    ++$total_debits if $_->{type} eq "debit";

    $_->{ts} = str2time($_->{date});
    $_->{isodate} = strftime("%FZ", gmtime($_->{ts}));
    $_->{cname} = "$_->{account}: $_->{desc}";

    $_->{mapped_account} = determine_account($_->{account});
    $_->{tags} = determine_tags($_->{mapped_account}, $_->{type}, $_->{desc});

    if(!defined $_->{mapped_account}) {
        if(!defined $accounts_not_found{$_->{account}}) {
            $accounts_not_found{$_->{account}} = 0;
            print "WARNING: Account not found [$_->{account}]\n";
        }
        ++$accounts_not_found{$_->{account}};
        ++$account_nonhits;
    }

    if(!defined $_->{tags}) {
        $desc_not_found{$_->{type}} = {} if !defined $desc_not_found{$_->{type}};
        $desc_not_found{$_->{type}}->{$_->{account}} = {} if !defined $desc_not_found{$_->{type}}->{$_->{account}};
        if(!defined $desc_not_found{$_->{type}}->{$_->{account}}->{$_->{desc}}) {
            $desc_not_found{$_->{type}}->{$_->{account}}->{$_->{desc}} = 0;
            ++$unique_credit_nonhits if $_->{type} eq "credit";
            ++$unique_debit_nonhits if $_->{type} eq "debit";
        }
        print "WARNING: Desc not found: $_->{type} $_->{mapped_account} /^$_->{desc}/ \n";
        ++$desc_not_found{$_->{type}}->{$_->{account}}->{$_->{desc}};
        ++$desc_nonhits;
        ++$credit_nonhits if $_->{type} eq "credit";
        ++$debit_nonhits if $_->{type} eq "debit";
    }
}


printf "Total Transactions:   %d (%d credits, %d debits)\n", $total_transactions, $total_credits, $total_debits;
printf "Account hits:         %d\n", $total_transactions - $account_nonhits;
printf "Account non-hits:     %d\n", $account_nonhits;
printf "Description hits:     %d\n", $total_transactions - $desc_nonhits;
printf "Description non-hits: %d (%d credits(%d), %d debits(%d))\n", $desc_nonhits, $credit_nonhits, $unique_credit_nonhits, $debit_nonhits, $unique_debit_nonhits;








exit;
