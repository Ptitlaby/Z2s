# Z2s
Zkillboard to Slack

Z2s is a small perl script which will check regularly your alliance killboard by using Zkillboard API.

You will want to edit several variables before starting :

$alliance_ID : put your alliance ID 
$slackURL : You need to put there the incoming webhook URL from Slack. You can create one on Slack in the Integrations menu (you need to be admin for it)
$slack_Channel : The channel where you want the bot to post your stuff
$timeout : The time between two checks
