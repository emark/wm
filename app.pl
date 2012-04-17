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
my @ln=();


print "Ok, let's start!\nClearing database\n";
$dbi->delete_all(table=>'prod');

print 'Get list of items...';
$tx=$ua->max_redirects(5)->get('http://video.wikimart.ru/camcoders/camcorder/?price[to]=6500&price[from]=2500&order=popularity'=>{DNT=>1})->res->dom;

for my $l ($tx->find('.InfoModel a')->each){
	push @ln, $l->attrs('href');
}
say "Ok\nStarting parse product pages\n";
my $allitems=@ln;
my $n=0;
foreach my $link(@ln){
	$n++;
	print  "Product\t#$n\tfrom\t$allitems\t";
	$tx=$ua->max_redirects(5)->get($link=>{DNT=>1})->res->dom;
	my %prod=();
	
	$prod{'link'}=$link;

	for my $c($tx->find('#information h1')->each){
    	$prod{'caption'}= $c->text;
	}

	for my $p($tx->find('.photo')->each){
    	$prod{'image'}= $p->attrs('src');
	}

	for my $l ($tx->find('.offer-price')->each){
    	$prod{'price'}=$l->all_text;
	    $prod{'price'}=~s/\s+||\р\.//g;
	}

	for my $desc($tx->find('.short-description-uncut p')->each){
    	$prod{'description'}=$desc->text;
	}

	for my $count($tx->find('.Count')->each){
    	$prod{'count'}=$count->text;
	}
	

	say "data recording\n";
	$dbi->insert({link=>$prod{'link'},caption=>$prod{'caption'},image=>$prod{'image'},price=>$prod{'price'},description=>$prod{'description'},count=>$prod{'count'}},table=>'prod');
	#foreach my $key(keys %prod){
    #	say "$key=$prod{$key}";
	#}
}

