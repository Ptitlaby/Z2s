#!/usr/bin/perl -w
use strict;
use warnings;
use LWP;
use JSON qw( decode_json );
use Data::Dumper;
use List::Util qw[min max];

# Config Alliance Query
my $alliance_Endpoint = "https://zkillboard.com/api/corporation";
# 99004364 Exit Strategy...
# 99000652 Blue
my $alliance_ID = 1390846542;
my @alliance_Options = ("no-items","no-attackers");
my $alliance_LastKillId = 50971255;
my %listOfKills = ();
# Config Single Kill Query
my $kill_Endpoint = 'https://zkillboard.com/api/killID';
my $kill_ID = -1;
my @kill_Options = ("no-items");

# Ship file
my %listOfShips = ();
my $itemname_File = 'itemname.csv';

# Slack config
# Beehive
#my $slack_URL = 'https://hooks.slack.com/services/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';
my $slack_URL = 'https://hooks.slack.com/services/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';
my $slack_Channel = '#killmails';
my $slack_Username = 'z2s';
my $slack_icon = ':ghost:';

my $timeout = 120;
while (1) {
    my $start = time;
    checkForNewKills();
    my $end = time;
    my $lasted = $end - $start;
    if ($lasted < $timeout) {  
        sleep($timeout - $lasted);
    }
};


exit;


sub checkForNewKills
{
	my $url = buildUrlAlly();
	my $return = queryZkillboard($url);
	my $decondedJson = analyzeJsonAlly($return);
}

sub buildUrlAlly
{
	my $url;
	$url = $alliance_Endpoint.'/'.$alliance_ID;
	for (@alliance_Options)
	{
		$url = $url.'/'.$_;
	}
	if ($alliance_LastKillId != 0)
	{
		$url = $url.'/afterKillID/'.$alliance_LastKillId;
	}

	return $url
}

sub queryZkillboard
{
	my ($url) = @_;
	my $result='fail';

	my $ua = LWP::UserAgent->new;
	$ua->agent("Z2s Bot - Author : Alyla By - laby \@laby.fr");

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

sub analyzeJsonAlly
{
	my ($json) = @_;
	if ($json eq 'fail')
	{
		return;
	} 
	my $struct = decode_json($json);

	my $killId = 0;
	my $killDate = '';
	my $killValue = '';

	# Dumping to file
	my $filename = 'json.txt';
	open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
	#print $fh Dumper($struct);

	my @aUnref = @{ $struct };
	#print $fh Dumper(@aUnref);

	for(@aUnref)
	{
		my %hUnref = %{ $_ };
		$killId = $hUnref{'killID'};
		$killDate = $hUnref{'killTime'};
		$killValue = $hUnref{'zkb'}{'totalValue'};

		my $tmpUrl = buildUrlKill($killId);
		my $killJson = queryZkillboard($tmpUrl);
		$alliance_LastKillId = max($killId,$alliance_LastKillId);
		analyzeJsonKill($killJson);
	}
}

sub buildUrlKill
{
	my ($killId) = @_;
	my $url;
	$url = $kill_Endpoint.'/'.$killId;
	for (@kill_Options)
	{
		$url = $url.'/'.$_;
	}
	return $url
}

sub analyzeJsonKill
{
	my ($json) = @_;
	if ($json eq 'fail')
	{
		return;
	}
	my $struct = decode_json($json);
	#my $filename = 'json.txt';
	#open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
	#print $fh Dumper($struct);

	my @aUnref = @{ $struct };
	#print $fh Dumper(@aUnref);
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
	for(@attackers)
	{
		my %hashAttacker = %{$_};
		if ( $hashAttacker{'allianceID'} == $alliance_ID )
		{
			$numberAttackers++;
		}
	}
	if ($numberAttackers == 0)
	{
		$numberAttackers = scalar @attackers;
	}

	my $lossValue = $hUnref{'zkb'}{'totalValue'};
	$lossValue = formatNumber($lossValue);
	my $victimID = $hUnref{'victim'}{'characterID'};
	my $victimName = $hUnref{'victim'}{'characterName'};
	my $victimCorp = $hUnref{'victim'}{'corporationName'};
	my $victimAllyID = $hUnref{'victim'}{'allianceID'};
	my $victimAlly = $hUnref{'victim'}{'allianceName'};
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

	# corp
	if ($victimAllyID ne $alliance_ID )
	{
		$msg = $msg.' from Beehive-Surveillance killed ';
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
	}
	return $shipId;
}

sub sendToSlack
{
	my ($msg) = @_;
	my $ua = LWP::UserAgent->new;
	my $req = HTTP::Request->new(POST => $slack_URL);
	$ua->agent("Z2s Bot - Author : Alyla By - laby \@laby.fr");
	 
	# add POST data to HTTP request body
	#toto
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

