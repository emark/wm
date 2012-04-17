#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.12;

my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();

$tx=$ua->get('http://video.wikimart.ru/camcoders/extrim_videocamera/model/12704522/videokamery_dlja_ehkstrima_ehkshn-kamera_mysee_x/')->res->dom;

my %prod=();

for my $c($tx->find('#information h1')->each){
	$prod{'caption'}= $c->text;
}

#Parse image source
for my $p($tx->find('.photo')->each){
	$prod{'image'}= $p->attrs('src');
}

#Get item price
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
