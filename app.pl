#!/usr/bin/perl -w
use strict;
use Mojo::UserAgent;
use Mojo::DOM;
use utf8;
use v5.10;
use DBIx::Custom;
use File::Copy;

my $dbi=DBIx::Custom->connect(dsn=>"dbi:SQLite:dbname=db/database");
my $ua=Mojo::UserAgent->new();
my $tx=Mojo::DOM->new();
my @ln=();#product links from subcategory list
my $catfile='catalog.csv';
my @catalog=();#catalog list
my $catcount=0;#count of catalog categories
my $topcat;
my $subcat;
my @commands = (
	'Quit',
	'Update catalog (only)',
	'Add new products (only)',
	'Update and add products',
	'Update products preview (only)',
	'Download and update products preview',
	'Parse by product id',
);

given (&SelectCmd){
	when(1){
		say "\nStarting to $commands[1]";
		&UpdateCatalog;
		&CopyProductImage;
	}when(2){
		say "\nStarting to $commands[2]";
		&GetNewProd;
       	&DownloadProductImage;
		&CopyProductImage;
	}when(3){
		say "\nStarting to $commands[3]";
		&UpdateCatalog;
        &GetNewProd;
        &DownloadProductImage;
        &CopyProductImage;
	}when(4){
        say "\nStarting to $commands[4]";
        &CopyProductImage;
    }when(5){
		say "\nStarting to $commands[5]";
        &DownloadProductImage;
        &CopyProductImage;
	}when(6){
		say "\nStarting to $commands[6]";
		print 'Enter product id: ';
		my $id = <STDIN>;
		&ParseProductCard($id) if $id;
	}default {
		say 'Buy!'
	}
};

say 'All done at '.localtime(time);

sub SelectCmd(){
	say 'NOTE! Before starting see README';
	say 'Select command:';
	my $n = 0;
	foreach my $key (@commands){
		say "\t$n. $key";
		$n++;
	};
	print "Your choise: ";
	return <STDIN>;
};

sub UpdateCatalog(){
	my @id=();
	open (UPDATE,"< update.csv") || die "Can't open update file";	
	@id=<UPDATE>;
	close UPDATE;
	$dbi->update_all({status=>2},table=>'prod');#Mark all item as deleted
	foreach my $key (@id){
		chomp $key;
		$dbi->update({status=>3},table=>'prod',where=>{id=>$key});#Mark items as allowed from update.csv
		say "Status update, id=$key";
	}
	print 'Deleting marked id...';
	$dbi->delete(table=>'prod',where=>{status=>2});#Delete mared items
	say 'Done, databes updated';
	my $result=$dbi->select(
		['id','link'],
		table=>'prod',
		where=>{status=>3},
	);
	while(my $row=$result->fetch_hash){
		print "Update product info, id[$row->{'id'}]: ";
		&ParseProductCard($row->{'id'},$row->{'link'});
	}
}

sub GetNewProd(){
	say "Open catalog file: $catfile";
	open (CAT,"< $catfile") || die "Can't open $catfile file";
	@catalog = <CAT>;
	close CAT;
	$catcount = @catalog;
	say "Reading $catcount position(s)";

	my $c = 0;#catalog subcategory counter
	my $urlcat;my $pricefrom;my $priceto;my $orderby;
	foreach my $key(@catalog){#parsing catalog string
		$c++;
		chomp $key;
		($topcat,$subcat,$urlcat,$pricefrom,$priceto,$orderby) = split(';',$key);

		say "Top category: $topcat\nSubcategory: $subcat";
		$tx = $ua->max_redirects(5)->get("$urlcat?price[from]=$pricefrom&price[to]=$priceto&order=$orderby"=>{DNT=>1})->res->dom;
		@ln = ();#clear links array
		for my $l ($tx->find('.InfoModel a')->each){
			push @ln, $l->attrs('href');
		}
		say "Starting parse product pages\n";
		my $allitems = @ln;
		my $n = 0;
		foreach my $link(@ln){
			$n++;
			print "Product #$n from $allitems. Category $c from $catcount. ";
			my $result = $dbi->select(
				['id'],
				table => 'prod',
				where => {link => $link}
			);
			my $row = $result->fetch;
			if($row){
				say "Link exist. id[$row->[0]]";				
			}else{
				&ParseProductCard(0,$link);
			}
		}#foreach @ln
	}#foreach @catalog
}#sub GetNewProd

#Usage: ($id,$link)
sub ParseProductCard(){
	my $id = $_[0];
	my $link = '';
	#Development feature for parsing target product
	if($_[1]){
		$link = $_[1];
	}else{
		my $result = $dbi->select(
			column => 'link',
			table => 'prod',
			where => {'id' => $id},
		);
		$link = $result->fetch->[0];
	}

	$tx = $ua->max_redirects(5)->get($link=>{DNT=>1})->res->dom;
	
	my %prod = ();
	$prod{'link'} = $link;
	for my $c($tx->find('#information h1')->each){
		$prod{'caption'}= $c->text;
	};
	for my $p($tx->find('.photo')->each){
		$prod{'image'}= $p->attrs('src');
	};
	for my $l ($tx->find('.offer-price')->each){
		$prod{'price'}=$l->all_text;$prod{'price'}=~s/\s+||\р\.//g;
	};
	my $properties = '';
	my @propname = ();
	my @propvalue = ();
	for my $prop($tx->find('div.properties-group > dl.ui-helper-clearfix > dt > span')->each){
		push @propname, $prop->text;
	};

	for my $prop($tx->find('div.properties-group > dl.ui-helper-clearfix > dd')->each){
		push @propvalue, $prop->text;
	};
	my $p=0;#properties count
	foreach my $key(@propname){
		$properties = $properties.$key."=".$propvalue[$p]."; ";
		$p++;
	}
	for my $count($tx->find('p.Count')->each){
		$prod{'count'}=$count->text;
	};

	if($id == 0){
		$dbi->insert(
			{
				topcat => $topcat,
				subcat => $subcat,
				link => $prod{'link'},
				caption => $prod{'caption'},
				image => $prod{'image'},
				price => $prod{'price'},
				description => $properties,
				count => $prod{'count'},
				status => 0,
			},
			table => 'prod'
		);
		say 'Insert';
	}else{
		my $result=$dbi->select(
			['price'],
			table => 'prod',
			where => {id => $id}
		);#set current price
		
		my $cur_price=0;
		
		while(my $row=$result->fetch){
			print "[$row->[0]]=[$prod{'price'}] ";
			$cur_price = $row->[0];
		}

		if($cur_price<$prod{'price'}){
			$dbi->update(
				{
					price => $prod{'price'},
					count => $prod{'count'},
					status => 1
				},
				table => 'prod',
				where => {id => $id}
			);
			say 'Update';
		}elsif(!$prod{'price'}){
			$dbi->update(
				{status => 2},
				table => 'prod',
				where => {id => $id}
			);
			say 'Break link. Deleted';
		}else{
			say 'Not updated';
		}
	}
}#sub ParseProductCard

sub DownloadProductImage(){
	#NOTE! Move all product images from products catalog to temp

	chdir 'media/temp/';
	#Download new product images in temp catalog	
	my $result=$dbi->select(
			['id','image','count','description'],
			table=>'prod',
			where=>'length(image)>0 and status=0',
	);

	while(my $row=$result->fetch_hash){
    	say "Get preview image to id: $row->{'id'}";
	    $tx=$ua->max_redirects(5)->get($row->{'image'}=>{DNT=>1})->res->content->asset->move_to($row->{'id'}.'.jpeg');
	};

	chdir '../../';
}

sub CopyProductImage(){
	my $result = $dbi->select(
        column => 'id',
        table => 'prod',
        where => 'status != 2 and length(image)>0',
    );

    say 'Starting to copy product images';
    while(my $row = $result->fetch_hash){
        say "Copy id $row->{'id'}";
        copy("media/temp/$row->{'id'}.jpeg","media/products/$row->{'id'}.jpeg") || die "Can't copy file: $row->{'id'}.jpeg";
    };
}
