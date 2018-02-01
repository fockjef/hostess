#!/usr/bin/perl

use strict;
use Getopt::Long;
use LWP::UserAgent;

my %Config = (
    custom => [
        {host=>'localhost',addr=>'127.0.0.1'},
        {host=>'localhost ip6-localhost ip6-loopback',addr=>'::1'},
        {host=>'ip6-allnodes',addr=>'ff02::1'},
        {host=>'ip6-allrouters',addr=>'ff02::2'},
    ],
    sources => [
        {name=>'airel',type=>'mis' ,weight=>0.35,url=>'http://rlwpx.free.fr/WPFF/hmis.7z'},
        {name=>'airel',type=>'pub' ,weight=>0.35,url=>'http://rlwpx.free.fr/WPFF/hpub.7z'},
        {name=>'airel',type=>'rsk' ,weight=>0.35,url=>'http://rlwpx.free.fr/WPFF/hrsk.7z'},
        {name=>'airel',type=>'sex' ,weight=>0.00,url=>'http://rlwpx.free.fr/WPFF/hsex.7z'},
        {name=>'airel',type=>'trc' ,weight=>0.35,url=>'http://rlwpx.free.fr/WPFF/htrc.7z'},
        {name=>'camel',type=>''    ,weight=>0.95,url=>'http://sysctl.org/cameleon/hosts'},
        {name=>'hfnet',type=>'main',weight=>0.35,url=>'http://hosts-file.net/download/hosts.zip'},
        {name=>'hfnet',type=>'part',weight=>0.35,url=>'http://hosts-file.net/hphosts-partial.txt'},
        {name=>'hforg',type=>''    ,weight=>0.65,url=>'http://hostsfile.org/Downloads/BadHosts.msw.zip'},
        {name=>'moaab',type=>''    ,weight=>0.30,url=>'http://adblock.mahakala.is/'},
        {name=>'mvps' ,type=>''    ,weight=>0.95,url=>'http://winhelp2002.mvps.org/hosts.zip'},
        {name=>'mware',type=>''    ,weight=>0.95,url=>'http://www.malwaredomainlist.com/hostslist/hosts.txt'},
        {name=>'s1who',type=>''    ,weight=>0.95,url=>'http://someonewhocares.org/hosts/hosts'}
    ],
    whitelist => [qw/localhost local localhost.localdomain android.localhost test.localhost broadcasthost android test/],
    source_dir  => "sources",
    block_score => 1.0,
    block_addr  => "0.0.0.0",
    hosts_file  => "hosts"
);

my %Opts = (
    download => 1
);
GetOptions("download!"=>\$Opts{download});

if( !-d $Config{source_dir} ){
    mkdir $Config{source_dir} or die "ERROR: Cannot create directory '$Config{source_dir}'";
}

my $ua = LWP::UserAgent->new();
$ua->agent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/62.0.3202.89 Safari/537.36');

my %Hosts;

foreach my $s (@{$Config{sources}}){
    print STDERR $s->{name}, " ", ($s->{type}?"($s->{type})":""), ":\n";
    my $ext = ($s->{url} =~ /\.([^\/.]+?)$/)[0] || "txt";
    my $file = $Config{source_dir}."/".$s->{name}.($s->{type}?"-".$s->{type}:"").".".$ext;

    if( $Opts{download} ){
        print STDERR "\tDownloading\t";
        my $res = $ua->mirror($s->{url},$file);
        print STDERR $res->is_error ? "ERROR [ ".$res->status_line." ]\n" : ( $res->is_redirect ? "Not Modified\n" : (-s $file)." bytes\n");
    }
    
    print STDERR "\tProcessing\t";
    my $n = 0;
    open my $DATA, $ext eq "txt" ? $file : "7z e -so $file 2>/dev/null |" or die "ERROR: Cannot open file '$file'";
    foreach my $h (map {(split)[1]} grep {/^\s*(?:127\.0\.0\.1|0\.0\.0\.0)\s+/} <$DATA>){
        if( !exists $Hosts{$h}{$s->{name}} || $Hosts{$h}{$s->{name}} < $s->{weight} ){
            $Hosts{$h}{SCORE} += $s->{weight}-$Hosts{$h}{$s->{name}};
            $Hosts{$h}{$s->{name}} = $s->{weight};
        }
        $n++;
    }
    print STDERR "$n hosts\n";
}

delete @Hosts{@{$Config{whitelist}}};
my @Blocked = grep { $Hosts{$_}{SCORE} >= $Config{block_score} } keys %Hosts;
print STDERR "Blocked ".scalar(@Blocked)." hosts\n";

open my $OUT, ">$Config{hosts_file}";
print $OUT join "\n", map { sprintf "%-15s\t%s", $_->{addr}, $_->{host} } @{$Config{custom}};
print $OUT "\n\n";
print $OUT join "\n", map { sprintf "%-15s\t%s", $Config{block_addr}, $_ } sort @Blocked;
close $OUT;
