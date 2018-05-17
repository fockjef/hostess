#!/usr/bin/perl

use strict;
use Getopt::Long;
use JSON;
use List::Util qw(sum);
use LWP::UserAgent;

our $VERSION = "1.0.20180517";

my $NULL = $^O eq "MSWin32" ? "NUL" : "/dev/null";

my %Opts = (
	config => 'hostess.conf',
	download => 1
);
GetOptions(
	"config:s"=>\$Opts{config},
	"download!"=>\$Opts{download}
);

my $json = do{local $/;open my $IN, $Opts{config} or die "ERROR: Cannot open config file ($Opts{config})";<$IN>};
my $Config = eval { decode_json $json } or die "ERROR: Cannot parse json";

if( !-d $Config->{source_dir} ){
    mkdir $Config->{source_dir} or die "ERROR: Cannot create directory '$Config->{source_dir}'";
}

my $ua = LWP::UserAgent->new();
$ua->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.89 Safari/537.36');

my %Hosts;

foreach my $s (@{$Config->{sources}}){
    print STDERR $s->{name}, " ", ($s->{type}?"($s->{type})":""), ":\n";
    my $ext = ($s->{url} =~ /\.([^\/.]+?)$/)[0] || "txt";
    my $file = $Config->{source_dir}."/".$s->{name}.($s->{type}?"-".$s->{type}:"").".".$ext;

    if( $Opts{download} ){
        print STDERR "\tDownloading\t";
        my $res = $ua->mirror($s->{url},$file);
        print STDERR $res->is_error ? "ERROR [ ".$res->status_line." ]\n" : ( $res->is_redirect ? "Not Modified\n" : (-s $file)." bytes\n");
    }
    
    print STDERR "\tProcessing\t";
    my $n = 0;
    open my $DATA, ($ext eq "txt" ? $file : "7z e -so $file 2>$NULL |") or die "ERROR: Cannot open file '$file'";
    foreach my $h (map {(split)[1]} grep {/^\s*(?:127\.0\.0\.1|0\.0\.0\.0)\s+/} <$DATA>){
        if( !exists $Hosts{$h}{$s->{name}} || $Hosts{$h}{$s->{name}} < $s->{weight} ){
            $Hosts{$h}{SCORE} += $s->{weight}-$Hosts{$h}{$s->{name}};
            $Hosts{$h}{$s->{name}} = $s->{weight};
        }
        $n++;
    }
    print STDERR "$n hosts\n";
}

delete @Hosts{@{$Config->{whitelist}}};
my @Blocked = grep { $Hosts{$_}{SCORE} >= $Config->{block_score} } keys %Hosts;
print STDERR "Blocked ".scalar(@Blocked)." hosts\n";

open my $OUT, ">$Config->{hosts_file}";
print $OUT join "\n", map { sprintf "%-15s\t%s", $_->{addr}, $_->{host} } @{$Config->{custom}};
print $OUT "\n\n";
print $OUT join "\n", map { sprintf "%-15s\t%s", $Config->{block_addr}, $_ } sort @Blocked;
close $OUT;
