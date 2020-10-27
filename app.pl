#!/usr/bin/perl -w

use strict;

use Mojo::UserAgent;
use Mojo::DOM;

use utf8;
use v5.10;

use DBIx::Custom;
use File::Copy;

my $VERSION = '0.9.2';
my $dev = 0;

my $dbi = DBIx::Custom->connect(dsn=>"dbi:SQLite:dbname=db/database");
my $ua = Mojo::UserAgent->new();
my $tx = Mojo::DOM->new();
my @ln = ();#product links from subcategory list
my $catfile = 'catalog.csv';
my @catalog = ();#catalog list
my $catcount = 0;#count of catalog categories
my $topcat;
my $subcat;
my $cmd = '';
my @result = ('Ok','Error');#status of execute 
my $errmsg = '';
my @commands = (
	'Quit',
	'Update price',
	'Add new products',
	'Update price and add new products',
	'Copy products images /temp->/products',
	'Download and copy products images',
	'Parsing by ID',
	'Update product image (new source)',
	'Update product image (new sorce) from list',
	'Export all data',
	'Export status of products',
);

print "Webparser $VERSION\nhttp://github.com/emark/wm.git\n\n";

do {
	$cmd = &SelectCmd;	

	say "/$commands[$cmd]/"; 
	say 'Starting new job at '.localtime(time);
	
	if ($cmd == 1){
		&UpdateCatalog;
		&CopyProductImage;
	
	} elsif ($cmd == 2){
		&GetNewProduct;
		&DownloadProductImage;
		&CopyProductImage;
	
	} elsif ($cmd == 3){
		&UpdateCatalog;
       	&GetNewProduct;
       	&DownloadProductImage;
       	&CopyProductImage;

	} elsif ($cmd == 4){
       	&CopyProductImage;

   	} elsif ($cmd == 5){
       	&DownloadProductImage;
       	&CopyProductImage;

	} elsif ($cmd == 6){
		print 'Enter product ID: ';
		my $id = <STDIN>;
		&UpdateProductPrice($id);
		#print "Function disabled";
		#&ParseProductCard($id) if $id;

	} elsif ($cmd == 7){
		&UpdateProductItem;

	} elsif($cmd == 8){
		&UpdateProductItemFromList;

	}elsif ($cmd == 9){
		&ExportData;

	} elsif ($cmd == 10){
		&CheckIdStatus;

	} elsif ($cmd == 0) {
		say 'Exit. Buy!'
	}

	say 'Job is finished at '.localtime(time);

} while ($cmd!=0);

sub SelectCmd(){
	say "\nPlease, select command:";
	my $n = 0;
	foreach my $key (@commands){
		say "\t[$n] - $key";
		$n++;
	};
	print "\nEnter number: ";
	return <STDIN>;
};

sub UpdateCatalog(){

	my @id=();
	my $n = 1;

	open (UPDATE,"< update.csv") || die "Can't open update file";	
	@id=<UPDATE>;
	close UPDATE;

	$dbi->update_all(
		{ status => 2 }, 
		table => 'prod'
	);#Mark all item as deleted

	foreach my $key (@id){
		chomp $key;
		$dbi->update(
			{ status => 3 },
			table => 'prod',
			where => { id => $key }
		);#Mark items as allowed from update.csv

		say "Status updated, ID=$key";
	}

	print 'Remove the marked products...';

	$dbi->delete(
		table => 'prod', 
		where => { status => 2 }
	);#Delete mared items

	say 'Done';

	my $result=$dbi->select(
		['id','link'],
		table => 'prod',
		where => { status => 3 },
	);
	
	while(my $row=$result->fetch_hash){
		print "Updating product price: $n/".@id." ID [$row->{'id'}]: ";
		&UpdateProductPrice($row->{'id'},$row->{'link'});
		$n++;
	}
}

sub GetNewProduct(){
	say "Open catalog file: $catfile";
	open (CAT,"< $catfile") || die "Can't open $catfile file";
	@catalog = <CAT>;
	close CAT;
	$catcount = @catalog;
	say "Reading $catcount position(s)";

	my $c = 0;#catalog subcategory counter
	my $store;
	my $urlcat; 
	my $pricefrom;
	my $priceto;
	my $orderby;
	foreach my $key(@catalog){#parsing catalog string
		$c++;
		chomp $key;
		($store,$topcat,$subcat,$urlcat,$pricefrom,$priceto,$orderby) = split(';',$key);

		say "Top category: $topcat\nSubcategory: $subcat";
		$tx = $ua->max_redirects(5)->get("$urlcat"=>{DNT=>1})->res->dom;
		@ln = ();#clear links array

		for my $l ($tx->find('div .indexGoods__item__descriptionCover a')->each){
		
			push @ln, $store.$l->attr('href') if ($l->attr('href') ne '#');
		
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

				&UpdateProductPrice(0, $link);
				#&ParseProductCard(0,$link);
		
			}
		}#foreach @ln
	}#foreach @catalog
}#sub GetNewProd

#Usage: ($link)
sub ParseProductCard(){

	my $link =$_[0];
	$tx = $ua->max_redirects(5)->get($link=>{DNT=>1})->res->dom;

	my %prod = ();
	$prod{'link'} = $link;


	#for my $c($tx->find('div.model-header > div.title')->each){
	for my $c($tx->find('h1')->each){

		my $caption = $c->text;
		utf8::encode $caption;	
		$prod{'caption'}= $caption;
	};

	my $l = ($tx->find('div.p__displayedItem__images__big a')->first);
	$prod{'image'} = $tx->all_text;
	$prod{'image'} = $l->attr('href');
	
	$l = ($tx->find('span.js__actualPrice')->first);
	if ($l){
		$prod{'price'}=$l->all_text;
		$prod{'price'}=~s/\s+|\₽//g;
	};

	for my $prop($tx->find('div.descriptionText_cover p')->each){
		$prod{'descripion'} = $prop->text;
		utf8::encode $prod{'descripion'}; 
	};
	
	my @propname = ();
	my @propvalue = ();
	my $prop_text = '';

	for my $coll ($tx->find('ul.featureList > li.featureList__item > span')->each){
	
		$prop_text = $coll->text;
		utf8::encode $prop_text;
		push @propname, $prop_text;
	};

	for my $coll ($tx->find('ul.featureList > li.featureList__item')->each){

		$prop_text = $coll->text;
		utf8::encode $prop_text;
		push @propvalue, $prop_text;
	};

	my $n = 0;
	$prod{prop} = '';
	foreach my $key (@propname){
		$prod{prop} = $prod{prop}. $key.'='.$propvalue[$n].'; ';
		$n++;
	};

	$prod{'count'} = 0;	
	for my $offers($tx->find('span.catalog__displayedItem__availabilityCount > label')->each){
		$prod{'count'} = $offers->text;#More than one offer
	};

#Development: see product parameters 
#
	if ($dev){
		foreach (keys %prod){
			say "$_ = $prod{$_}";
		};
		exit;
	};
#
return %prod;
}#sub ParseProductCard


#Usage: ($id,$link)
sub UpdateProductPrice(){

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

	my %prod= ();
	%prod = &ParseProductCard($link);

	if($id == 0){
		$dbi->insert(
			{
				topcat => $topcat,
				subcat => $subcat,
				link => $prod{'link'},
				caption => $prod{'caption'},
				image => $prod{'image'},
				price => $prod{'price'},
				description => $prod{'prop'},
				count => $prod{'count'},
				status => 0,
			},
			table => 'prod'
		);
		say 'Product added.';

	}else{
		my $result=$dbi->select(
			['price'],
			table => 'prod',
			where => {id => $id}
		);#set current price
		
		my $cur_price = 0;
		
		while (my $row=$result->fetch){
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
			say 'Updated';

		}elsif(!$prod{'price'}){
			$dbi->update(
				{status => 2},
				table => 'prod',
				where => {id => $id}
			);
			say 'New price not found. Product removed.';

		}else{
			say 'Not updated';

		}
	}
}

sub DownloadProductImage(){
	#NOTE! Move all product images from products catalog to temp

	chdir 'media/temp/';
	#Download new product images in temp catalog	
	my $result=$dbi->select(
			['id','image'],
			table => 'prod',
			where => 'length(image)>0',
	);

	while(my $row=$result->fetch_hash){
    	say "Get preview image to id: $row->{'id'}";
		my $ext = $row->{'image'};
		$ext =~s/^.+\.//;
	    $tx=$ua->max_redirects(5)->get($row->{'image'}=>{DNT=>1})->res->content->asset->move_to($row->{'id'}.'.'.$ext);
	};

	chdir '../../';
}

sub CopyProductImage(){
	my $result = $dbi->select(
        column => ['id', 'image'],
        table => 'prod',
        where => 'status != 2 and length(image)>0',
    );

    say 'Starting to copy product images';
    while(my $row = $result->fetch_hash){
        say "Copy id $row->{'id'}";
		my $ext = $row->{'image'};
		$ext =~s/^.+\.//;
        copy("media/temp/$row->{'id'}.$ext","media/products/$row->{'id'}.$ext") || die "Can't copy file: $row->{'id'}.$ext";
    };
}

sub ExportData(){
	my $file = 'data.csv';
	my $separator = '@';
	my $result = $dbi->select(
		table => 'prod',
	);
	
	open (FILE,"> $file") || die "Can't open target file $file";

	foreach my $header (@{$result->header}){
		print FILE $header.'@';
	};
	print FILE "=ROUND(G1*1.6,0)\n";

	while (my $row = $result->fetch){
		foreach my $i (@{$row}){
			print FILE $i;
			print FILE $separator;
		};
		print FILE "\n";
	};

	close FILE;
	return 1;
}

sub CheckIdStatus(){
my @id = ();
open(FILE,"< update.csv") || die "Can't open update file";
@id = <FILE>;
close FILE;

my $result = $dbi->select(
	table => 'prod',
	column => ['id','status'],
	where => {id => [@id]},
	);
print "Write data to result.csv\n";
open (RESULT,">> result.csv") || die "Can't write to result";
while(my $row = $result->fetch){
	print RESULT "$row->[0];$row->[1]\n";
	};
close RESULT;

}

sub UpdateProductItem(){

my $id = 0;

if($_[0]){

	$id = $_[0];
}else{

	say 'Enter product ID[0 - for all]: ';
	$id = <STDIN>;
}

my $result = '';

if($id>0){

	say 'Select one product ';
	$result = $dbi->select(
		
		table => 'prod',
		column => ['id','link'],
		where => {id => $id},
	);
}else{

	say 'Select all products';
	$result = $dbi->select(
		table => 'prod',
		column => ['id','link'],
	);
}

my %prod = ();

my $n = 0;

while (my $row = $result->fetch_hash){
	
	print "\nId: $row->{id}\t\n";
	%prod = &ParseProductCard($row->{link});
	
	if ($prod{image}){
	
		$dbi->update(
			{image => $prod{'image'}},
			table => 'prod',
			where => {id => $row->{id}},
		);
	};
	$n++;
	
	print "$n: $prod{image}\n";
};

sub UpdateProductItemFromList(){
	
	say 'Reading from file: list.csv';
	my @list = ();

	open (LIST,"< list.csv") || die "Can't open source list";
	@list = <LIST>;	
	close LIST;

	foreach my $key (@list){

		chop($key);	
		print "Update item: [$key]\n";
		&UpdateProductItem($key);
	};
};

}
