#!/usr/bin/perl -w
use strict;
use warnings;
use LWP;
use JSON qw( decode_json );
use Data::Dumper;
use List::Util qw[min max];
use Cwd qw( abs_path );
use File::Basename;
my $dirname = dirname(__FILE__);


# Zkillboard Endpoints
my $zkAllyUrl = "https://zkillboard.com/api/allianceID/";
my $zkCorpUrl = "https://zkillboard.com/api/corporation/";
my $zkKillUrl = 'https://zkillboard.com/api/killID/';
# Zkillboard options
my @zkOptions = ("no-items","no-attackers");
my @zkKillOptions = ("no-items");


#Configuration
my $lastFile = $dirname."/z2s.last";
my $confFile = $dirname."/z2s.conf";
my @arrayLastKills;
# mode : 1 (Ally), 2 (Corp)
my $mode = 2;
my $entityId = 1390846542;
my $nbKeptKills = 50;
my $thousandDelimiter = " ";


# Ship file
my %listOfShips = ();
my $itemname_File = $dirname."/itemname.csv";

# Eve Online CREST Endpoint
my $CRESTUrl = "https://public-crest.eveonline.com/types/?page=";

# User agent
my $userAgent = "Z2s Bot - Author : Alyla By - laby \@laby.fr";

# Slack config
my $slack_URL = 'https://hooks.slack.com/services/CCC/BBB/AAA';
my $slack_Channel = '#killmails';
my $slack_Username = 'z2s';
my $slack_icon = ':ghost:';

my $timeout = 120;



readConfFile();
readKillFile();
checkForNewKills();
#writeKillFile();


exit;

sub readConfFile
{
	open(my $fh, "<", $confFile) or die "Could not open file '$lastFile' $!";
	for(<$fh>)
	{
		if ( /mode=(\d)\n/ )
		{
			$mode = $1;
		}
		if ( /corporationID=(\d)\n/ )
		{
			$entityId = $1;
		}
		if ( /allianceID=(\d)\n/ )
		{
			$entityId = $1;
		}
		if ( /thousandDelimiter=(.*)\n/ )
		{
			$thousandDelimiter = $1;
		}
		if ( /cacheSize=(\d)\n/ )
		{
			$nbKeptKills = $1;
		}
	}
}

sub readKillFile
{
	open (my $fh, "<", $lastFile) or die "Could not open file '$lastFile' $!";;
	for(<$fh>)
	{
		my $killId = $_;
		$killId =~ s/\n$//g;
		push @arrayLastKills, $killId;
	}
	close($fh);
	@arrayLastKills =  sort { $a <=> $b } @arrayLastKills;
	if ( @arrayLastKills == 0)
	{
		@arrayLastKills = push(@arrayLastKills, 0);
	}
}

sub writeKillFile
{
	# We keep only the last kills
	@arrayLastKills = sort { $a <=> $b } @arrayLastKills;
	while ( @arrayLastKills > $nbKeptKills )
	{
		shift @arrayLastKills;
	}

	open (my $fh, ">", $lastFile) or die "Could not open file '$lastFile' $!";;
	for(@arrayLastKills)
	{
		print $fh $_."\n";
	}
	close($fh);
}


sub checkForNewKills
{
	my $url = buildUrlCheckKills();
	my $return = httpQuery($url);
	if ($return eq 'fail') { return; }
	my $zkAnswer = decode_json($return);

	my @aUnref = @{ $zkAnswer };
	my @killsNotSent;

	for(@aUnref)
	{
		my %hUnref = %{ $_ };
		my $killId = $hUnref{'killID'};
		if ( !( grep(/$killId/,@arrayLastKills) ) )
		{
			push @killsNotSent, $killId;
			push @arrayLastKills, $killId;
		}
	}


	# Iteration on non sent kills 
	@killsNotSent = sort { $a <=> $b } @killsNotSent;
	for( @killsNotSent )
	{
		my $tmpUrl = buildUrlKillDetails($_);
		my $killJson = httpQuery($tmpUrl);
		analyzeJsonKill($killJson);
	}
}

sub buildUrlCheckKills
{
	my $url;

	# Ally or Corporation URL
	if ( $mode == 1)
	{
		$url = $zkAllyUrl.$entityId;
	}
	elsif ( $mode == 2)
	{
		$url = $zkCorpUrl.$entityId;
	}
	else
	{
		return;
	}

	# Kill we use as reference
	my $firstKillId = $arrayLastKills[0];
	$url = $url.'/afterKillID/'.$firstKillId;

	# Options for zKillboard
	for (@zkOptions)
	{
		$url = $url."/".$_;
	}

	return $url;
}



sub httpQuery
{
	my ($url) = @_;
	my $result='fail';

	my $ua = LWP::UserAgent->new;
	$ua->agent($userAgent);

	# set custom HTTP request header fields
	my $req = HTTP::Request->new(GET => $url);
	$req->header('content-type' => 'application/json');
	$req->header('Accept-Encoding' => 'gzip ');

	# Sending the request	 
	my $resp = $ua->request($req);
	if ($resp->is_success)
	{
		$result = $resp->decoded_content;
		#print "=================\n $result \n =================\n";
	}
	return $result;
}

sub buildUrlKillDetails
{
	my ($killId) = @_;
	my $url;
	$url = $zkKillUrl.$killId;
	for (@zkKillOptions)
	{
		$url = $url.'/'.$_;
	}
	return $url;
}

sub analyzeJsonKill
{
	my ($json) = @_;
	if ($json eq 'fail') { print "fail !"; return; }
	my $struct = decode_json($json);
	my @aUnref = @{ $struct };
	for(@aUnref)
	{
		my $msg = generateSlackMessage($_);
		sendToSlack($msg);
	}
}

sub formatNumber
{
	my ($number) = @_;
	my $firstPart;
	my $secondPart;

	if (index($number,'.') != -1)
	{
		my @splitResult = split(/\./,$number);
		$firstPart = $splitResult[0];
		$secondPart = $splitResult[1];
	}
	else
	{
		$firstPart = $number;
		$secondPart = '00';
	}

	my $firstReversed = reverse($firstPart);
	$firstReversed =~ s/([0-9]{1,3})/$1 /g;

	return reverse($firstReversed).'.'.$secondPart;
}

sub generateSlackMessage
{
	my ($hashRef) = @_;
	my %hUnref = %{ $hashRef };

	my $killId = $hUnref{'killID'};

	my @attackers = @{ $hUnref{'attackers'} };

	my $numberAttackers = 0;
	my $entityName;
	for(@attackers)
	{
		my %hashAttacker = %{$_};
		if (( ($mode == 1)&&($hashAttacker{'allianceID'} == $entityId) ) or ( ($mode == 2)&&($hashAttacker{'corporationID'} == $entityId) ))
		{
			$entityName = $hashAttacker{'corporationName'} || $hashAttacker{'allianceName'};
			$numberAttackers++;
		}
	}
	if ($numberAttackers == 0)
	{
		$numberAttackers = scalar @attackers;
	}

	my $lossValue = formatNumber($hUnref{'zkb'}{'totalValue'});
	my $victimID = $hUnref{'victim'}{'characterID'};
	my $victimName = $hUnref{'victim'}{'characterName'};
	my $victimCorp = $hUnref{'victim'}{'corporationName'};
	my $victimCorpID = $hUnref{'victim'}{'corporationID'};
	my $victimAlly = $hUnref{'victim'}{'allianceName'};
	my $victimAllyID = $hUnref{'victim'}{'allianceID'};
	
	my $victimShip = $hUnref{'victim'}{'shipTypeID'};

	my $killURL = 'https://zkillboard.com/kill/'.$killId;

	my $victimURL = 'https://zkillboard.com/character/'.$victimID;

	my $msg;
	$msg = $msg.$numberAttackers;

	# number of pilots
	if ($numberAttackers > 1)
	{
		$msg = $msg.' pilots';
	}
	else
	{
		$msg = $msg.' pilot';
	}

	# Ally 
	if ( $victimAllyID ne $entityId and $victimCorpID ne $entityId )
	{
		$msg = $msg." from $entityName killed ";
	}
	else
	{
		$msg = $msg.' killed ';
	}

	#ship name
	my $shipName = getShipName($victimShip);
	if ($shipName =~ /^[aeiouAEIOU]/)
	{
		$msg = $msg.'an '.$shipName;
	}
	else
	{
		$msg = $msg.'a '.$shipName;
	}
	$msg = $msg." piloted by <$victimURL|$victimName> ($victimCorp). Killmail value : $lossValue ISK (<$killURL|Link>)";


	return $msg;



}
sub getShipName
{
	my ($shipId) = @_;
	
	if ( exists $listOfShips{$shipId} )
	{
		return $listOfShips{$shipId};
	}
	else
	{

		open(my $fh, '<', $itemname_File) or die "Could not open file '$itemname_File' $!";
		for(<$fh>)
		{
			my $line = $_;
			my @splitResult = split(/\t/,$line);

			if ( $splitResult[0] eq $shipId )
			{
				$splitResult[1] =~ s/\n//g;
				$listOfShips{$shipId} = $splitResult[1];
				return $listOfShips{$shipId};
			}
		}

		return retrieveNameFromCREST($shipId);

	}
	
	return $shipId;
}

sub retrieveNameFromCREST
{
	my ($shipId) = @_;
	my $CRESTPage = 1;
	my $shipName = $shipId;
	my $CRESTPageCount = 2;
	
	
	do {
	
		my $currentURL = $CRESTUrl.$CRESTPage;
		
		my $json = httpQuery($currentURL);
		
		if ($json eq 'fail') { 
			print "fail !"; 
			return $shipName; 
		}
		
		my $data = decode_json($json);
		
		$CRESTPageCount = $data->{'pageCount'};
	
		$shipName = searchItem($shipId, @{$data->{'items'}});
		
		if ($shipName ne $shipId)
		{
			$listOfShips{$shipId} = $shipName;
			appendItemFile ($shipId, $shipName);
			return $shipName;
		}
		
		$CRESTPage ++;
	}
	while ($CRESTPage <= $CRESTPageCount);
	
	return $shipId;
}

sub searchItem
{
	my ($shipId, @items) = @_;

	
	foreach my $item (@items) 
	{
		my ($crestId) = $item->{'href'} =~ /.*types\/([0-9]*)\//;
		
		if ($crestId eq $shipId)
		{
			return $item->{'name'};
		}
	}
	
	return $shipId;
}

sub appendItemFile
{
	my ($shipId, $name) = (@_);
	my $line = $shipId . "\t" . $name;
	
	open (my $fh, ">>", $itemname_File) or die "Could not open file '$itemname_File' $!";;
	print $fh $line."\n";
	close($fh);
}

sub sendToSlack
{
	my ($msg) = @_;
	print $msg;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(POST => $slack_URL);
	$ua->agent("Z2s Bot - Author : Alyla By - laby \@laby.fr");
	 
	# add POST data to HTTP request body
	my $post_data = '{ "text":"'.$msg.'", "channel": "'.$slack_Channel.'" , "username":"'.$slack_Username.'", "icon_emoji":"'.$slack_icon.'"}';
	$req->content($post_data);
	 
	my $resp = $ua->request($req);
	if ($resp->is_success)
	{
	    my $message = $resp->decoded_content;
	    print time.": Sent message to Slack successfully\n";
	    #print "Received reply: $message\n";
	}
	else
	{
		print "Couldn't send message to Slack\n";
	    print "HTTP POST error code: ", $resp->code, "\n";
	    print "HTTP POST error message: ", $resp->message, "\n";
	}
}

