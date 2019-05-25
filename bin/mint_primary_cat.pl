#!/usr/bin/perl

use strict;
use warnings;

use Text::CSV;
use Date::Parse;
use Time::HiRes;
use POSIX qw(strftime);


my $input_file = shift || die "ERROR: Input filename required.\n";
my $final_balance = shift || 1012.89;
my $account_name = shift || "07 0 CHECKING A 0001";

my $csv=Text::CSV->new({binary=>1});
open my $fh, "<:encoding(utf8)",$input_file or die "ERROR: $input_file: $!\n";

$csv->column_names("date","mint_desc","desc","amount","type","mint_cat","account","mint_labels","mint_notes");
my $rows=$csv->getline_hr_all($fh,1);
$csv->eof or $csv->error_diag();
close $fh;

my @transactions = ();
my $oldest = undef;
my $newest = undef;

#print "Transactions as read:\n";
foreach(@{$rows}) {
    if($_->{account} eq $account_name) {
        my $t = {};
        $t->{ts} = str2time($_->{date});
        $oldest = $t->{ts} if !defined $oldest || $t->{ts} < $oldest;
        $newest = $t->{ts} if !defined $newest || $t->{ts} > $newest;

        $t->{date} = strftime("%F", localtime($t->{ts}));
        $t->{amount} = $_->{amount};
        $t->{type} = $_->{type};
        $t->{desc} = $_->{desc};
        $t->{mint_desc} = $_->{mint_desc};
        push @transactions, $t;
#        printf("%-11s %10.2f (%10.2f) %s\n", $t->{date}, ($t->{type} eq "credit" ? $t->{amount}:0), ($t->{type} eq "debit" ? $t->{amount}:0), $t->{desc});
    }
}

@transactions = sort {$a->{ts} <=> $b->{ts}} @transactions;

#print "\nTransactions with balance computations:\n";
my $cbal = $final_balance;
foreach(reverse @transactions) {
    my $t = $_;
    $t->{balance} = $cbal;

    if($t->{type} eq "credit") {
        $cbal -= $t->{amount};
    } elsif($t->{type} eq "debit") {
        $cbal += $t->{amount};
    }
#    printf("%-11s %10.2f %10.2f (%10.2f) %10.2f\n", $t->{date}, $cbal, ($t->{type} eq "credit" ? $t->{amount}:0), ($t->{type} eq "debit" ? $t->{amount}:0), $t->{balance});

}

sub computeDd {
    my ($ts) = @_;
    my (undef, undef, undef, $mday, $mon, $year, undef) = localtime($ts);
    $year += 1900;
    $mday -= 1;

    my $dd = ($year - 2000)*12 + $mon;

    # 30 days hath september, april, june, and november
    if($mon == 8 || $mon == 3 || $mon == 5 || $mon == 10) {
        $dd += $mday/31;
    } elsif($mon == 1) {
        $dd += $mday/31;
    } else {
        $dd += $mday/31;
    }

    return $dd;
}

sub computeM {
    my ($ts) = @_;
    my (undef, undef, undef, $mday, $mon, $year, undef) = localtime($ts);
    $year += 1900;
    $mday -= 1;

    my $mm = ($year - 2000)*12 + $mon;

    return $mm;
}


foreach(@transactions) {
    my $t = $_;
    my $date = $t->{date};
    my $dd = computeDd($t->{ts});
    my $mm = computeM($t->{ts});





}


exit;
