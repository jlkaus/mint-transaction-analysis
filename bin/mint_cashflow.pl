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

#print "\nDaily Balances:\n";

my %day_balances = ();
my %month_opens = ();

my $last_close = undef;
foreach(@transactions) {
    my $t = $_;
    my $date = $t->{date};
    my $dd = computeDd($t->{ts});
    my $d = $day_balances{$dd*31} // {date=>$date, dd => $dd, credits => 0, debits => 0, credit_total =>0, debit_total=> 0, net => 0};
    my $mm = computeM($t->{ts});

    if(!defined $month_opens{$mm}) {
        $month_opens{$mm} = $last_close;
    }

    if(!defined $d->{open}) {
        $d->{open} = $last_close;
        $d->{min} = $last_close;
        $d->{max} = $last_close;
    }
    $d->{close} = $t->{balance};
    $last_close = $t->{balance};
    if(!defined $d->{min} || $t->{balance} < $d->{min}) {
        $d->{min} = $t->{balance};
    }
    if(!defined $d->{max} || $t->{balance} > $d->{max}) {
        $d->{max} = $t->{balance};
    }

    if($t->{type} eq "credit") {
        ++$d->{credits};
        $d->{credit_total} += $t->{amount};
        $d->{net} += $t->{amount};
    } elsif($t->{type} eq "debit") {
        ++$d->{debits};
        $d->{debit_total} += $t->{amount};
        $d->{net} -= $t->{amount};
    }

    $day_balances{$dd*31} = $d if !defined $day_balances{$dd*31};
}

#printf("%-11s %10s %10s %10s %10s %10s %5s %10s\n","Date","FMonth","Open","Close","Min","Max","Count","Net","MRC");
#foreach(sort {$a <=> $b} keys %day_balances) {
#    my $dd = $_/31;
#    my $d = $day_balances{$dd*31};
#    my $m = int($dd);

#    printf("%-11s %10.3f %10.2f %10.2f %10.2f %10.2f %5d %10.2f %10.2f\n", $d->{date}, $d->{dd}, $d->{open}//-999, $d->{close}, $d->{min}, $d->{max}, $d->{credits} + $d->{debits}, $d->{net}, $d->{close} - $month_opens{$m});
#}

my %mday_metrics = ();

$last_close = undef;
for(my $i = $oldest; $i <= $newest; $i += 60*60*24) {
    my $dd = computeDd($i);
    my $mm = computeM($i);
    my $close = defined $day_balances{$dd*31} ? $day_balances{$dd*31}->{close} : $last_close;
    $last_close = $close;

    my $mrc = $close - $month_opens{$mm};

    my $md = int($dd*31) % 31;

    $mday_metrics{$md} = {count=>0, total=>0, squares=>0} if !defined $mday_metrics{$md};
    $mday_metrics{$md}->{min} = $mrc if !defined $mday_metrics{$md}->{min} || $mrc < $mday_metrics{$md}->{min};
    $mday_metrics{$md}->{max} = $mrc if !defined $mday_metrics{$md}->{max} || $mrc > $mday_metrics{$md}->{max};
    ++$mday_metrics{$md}->{count};
    $mday_metrics{$md}->{total} += $mrc;
    $mday_metrics{$md}->{squares} += $mrc * $mrc;


#    printf("%10.3f %10.2f %10.2f\n", $dd, $close, $mrc);
}

foreach(sort {$a <=> $b} keys %mday_metrics) {
    my $mean = $mday_metrics{$_}->{total} / $mday_metrics{$_}->{count};
    my $stddev = sqrt($mday_metrics{$_}->{squares}/$mday_metrics{$_}->{count} - $mean*$mean);


    printf("%3d %10.3f %10.3f %10.3f %10.3f %10.3f\n", $_+1, $mday_metrics{$_}->{min}, $mean - $stddev, $mean, $mean + $stddev, $mday_metrics{$_}->{max});

}

exit;
