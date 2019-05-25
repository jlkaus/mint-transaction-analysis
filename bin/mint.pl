#!/usr/bin/perl

use strict;
use warnings;

use Text::CSV;
use Date::Parse;
use Time::HiRes;
use POSIX qw(strftime);


my $input_file = shift || die "ERROR: Input filename required.\n";
my $sort_by_name = shift;


my $csv=Text::CSV->new({binary=>1});
open my $fh, "<:encoding(utf8)",$input_file or die "ERROR: $input_file: $!\n";

$csv->column_names("date","mint_desc","desc","amount","type","mint_cat","account","mint_labels","mint_notes");
my $rows=$csv->getline_hr_all($fh,1);
$csv->eof or $csv->error_diag();
close $fh;

my %accounts=();
my %cred_descs=();
my %deb_descs=();

foreach(@{$rows}) {
    $_->{ts} = str2time($_->{date});
    printf("%11s  %48s %10s %7s:  %s\n", strftime("%FZ", gmtime($_->{ts})), $_->{account}, $_->{amount}, $_->{type}, $_->{desc});
    $_->{cname} = "$_->{account}: $_->{desc}";

    $accounts{$_->{account}} = {credits=>0, debits=>0, tcount=>0, ccount=>0, dcount=>0} if !defined $accounts{$_->{account}};
    ++$accounts{$_->{account}}->{tcount};

    if($_->{type} eq "credit") {
        ++$accounts{$_->{account}}->{ccount};
        $accounts{$_->{account}}->{credits}+= $_->{amount};

        $cred_descs{$_->{cname}} = {credits=>0, count=>0} if !defined $cred_descs{$_->{cname}};

        ++$cred_descs{$_->{cname}}->{count};
        $cred_descs{$_->{cname}}->{credits}+= $_->{amount};


    } elsif($_->{type} eq "debit") {
        ++$accounts{$_->{account}}->{dcount};
        $accounts{$_->{account}}->{debits}+= $_->{amount};

        $deb_descs{$_->{cname}} = {debits=>0, count=>0} if !defined $deb_descs{$_->{cname}};

        ++$deb_descs{$_->{cname}}->{count};
        $deb_descs{$_->{cname}}->{debits}+= $_->{amount};
    }

}


print "\nAccounts:\n";
foreach(sort {$accounts{$b}->{tcount} <=> $accounts{$a}->{tcount}} keys %accounts) {
    printf "\t%9d (%9.2f,%9.2f)\t%s\n",$accounts{$_}->{tcount},$accounts{$_}->{credits},$accounts{$_}->{debits},$_;
}

if($sort_by_name) {
    print "\nCredit Descs:\n";
    foreach(sort keys %cred_descs) {
        printf "\t%9d (%9.2f)\t%s\n",$cred_descs{$_}->{count},$cred_descs{$_}->{credits},$_;
    }

    print "\nDebit Descs:\n";
    foreach(sort keys %deb_descs) {
        printf "\t%9d (%9.2f)\t%s\n",$deb_descs{$_}->{count},$deb_descs{$_}->{debits},$_;
    }
} else {
    print "\nCredit Descs:\n";
    foreach(sort {$cred_descs{$b}->{count} <=> $cred_descs{$a}->{count}} keys %cred_descs) {
        printf "\t%9d (%9.2f)\t%s\n",$cred_descs{$_}->{count},$cred_descs{$_}->{credits},$_;
    }

    print "\nDebit Descs:\n";
    foreach(sort {$deb_descs{$b}->{count} <=> $deb_descs{$a}->{count}} keys %deb_descs) {
        printf "\t%9d (%9.2f)\t%s\n",$deb_descs{$_}->{count},$deb_descs{$_}->{debits},$_;
    }
}

exit;
