#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.12;

my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();

$tx=$ua->get('http://video.wikimart.ru/camcoders/camcorder/?price[to]=6500&price[from]=2500&order=popularity')->res->dom;

for my $l ($tx->find('.InfoModel a')->each){
	say $l->attrs('href');
}

