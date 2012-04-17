#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.12;

my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();
my @ln=();

#Get products links from subcategory, order by popularity
$tx=$ua->get('http://video.wikimart.ru/camcoders/camcorder/?price[to]=6500&price[from]=2500&order=popularity')->res->dom;

for my $l ($tx->find('.InfoModel a')->each){
	push @ln, $l->attrs('href');
}


#Parse each product page
foreach my $link(@ln){
	$tx=$ua->get($link)->res->dom;

	my %prod=();

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

	foreach my $key(keys %prod){
    	say "$key=$prod{$key}";
	}
}

