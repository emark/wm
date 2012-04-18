#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.12;
use DBIx::Custom;

my $dbi=DBIx::Custom->connect(dsn=>"dbi:SQLite:dbname=db/database");
my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();
my @ln=();#product links from subcategory list
my $catfile='catalog.qr';
my @catalog=();#catalog list
my $catcount=0;#count of catalog categories


#&ParseProductCard('http://video.wikimart.ru/camcoders/camcorder/model/5840562/portativnaya_mini_videokamera_kodak_playsport_zx5/');

print "Ok, let's start!\nClearing database\n";
$dbi->delete_all(table=>'prod');

say "Open catalog file: $catfile";
open (CAT,"< $catfile") || die "Can't open $catfile file";
@catalog=<CAT>;
close CAT;
$catcount=@catalog;
say "Reading $catcount position(s)";

my $c=0;#catalog subcategory counter
my $topcat;my $subcat;my $urlcat;my $pricefrom;my $priceto;my $orderby;
foreach my $key(@catalog){
	$c++;
	chomp $key;
	($topcat,$subcat,$urlcat,$pricefrom,$priceto,$orderby)=split(';',$key);

	say "Top category: $topcat\nSubcategory: $subcat";
	$tx=$ua->max_redirects(5)->get("$urlcat?price[from]=$pricefrom&price[to]=$priceto&order=$orderby"=>{DNT=>1})->res->dom;

	for my $l ($tx->find('.InfoModel a')->each){
		push @ln, $l->attrs('href');
	}
	say "Starting parse product pages\n";
	my $allitems=@ln;
	my $n=0;
	foreach my $link(@ln){
		$n++;
		print  "Product #$n from $allitems. Category $c from $catcount.\t";
		&ParseProductCard($link);
	}#foreach @ln
}

sub ParseProductCard(){
	my $link=$_[0];
	$tx=$ua->max_redirects(5)->get($link=>{DNT=>1})->res->dom;
    my %prod=();

	$prod{'link'}=$link;

    for my $c($tx->find('#information h1')->each){$prod{'caption'}= $c->text;}
    for my $p($tx->find('.photo')->each){$prod{'image'}= $p->attrs('src');}
    for my $l ($tx->find('.offer-price')->each){$prod{'price'}=$l->all_text;$prod{'price'}=~s/\s+||\р\.//g;}
	$prod{'description'}='';
    for my $desc($tx->find('.description p')->each){$prod{'description'}=$prod{'description'}.$desc->text;}
    for my $count($tx->find('.Count')->each){$prod{'count'}=$count->text;}
    say "data recording\n";
    $dbi->insert({topcat=>$topcat,subcat=>$subcat,link=>$prod{'link'},caption=>$prod{'caption'},image=>$prod{'image'},price=>$prod{'price'},description=>$prod{'description'},count=>$prod{'count'}},table=>'prod');
}
