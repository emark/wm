#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.10;
use DBIx::Custom;

my $dbi=DBIx::Custom->connect(dsn=>"dbi:SQLite:dbname=db/database");
my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();
my @ln=();#product links from subcategory list
my $catfile='catalog.csv';
my @catalog=();#catalog list
my $catcount=0;#count of catalog categories
my $timestamp=time();

print "Ok, let's start!\n";

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
	@ln=();#clear links array
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

&GetImagePreview;
say 'All done at '.localtime(time);

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
    $dbi->insert({topcat=>$topcat,subcat=>$subcat,link=>$prod{'link'},caption=>$prod{'caption'},image=>$prod{'image'},price=>$prod{'price'},description=>$prod{'description'},count=>$prod{'count'}},table=>'prod');
	say 'Done.';
}

sub GetImagePreview(){
	chdir 'media/Products/';

	my $result=$dbi->select(['id','image','count','description'],table=>'prod',where=>'length(image)>0 and length(count)>0 and length(description)>0');

	while(my $row=$result->fetch_hash){
    	say "Get preview image to id: $row->{'id'}";
	    $tx=$ua->max_redirects(5)->get($row->{'image'}=>{DNT=>1})->res->content->asset->move_to($row->{'id'}.'.jpeg');
	}
}
