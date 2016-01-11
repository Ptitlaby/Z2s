# Z2s
Zkillboard to Slack

Z2s is a small perl script which will check regularly your alliance killboard by using Zkillboard API.
You have to setup a cron to run the task on a regular basis (at least 1 or 2 minutes).

You must edit the configuration file to match your settings first.
You also have to edit few variables in the main.pl before running the task.

$slackURL : You need to put there the incoming webhook URL from Slack. You can create one on Slack in the Integrations menu (you need to be admin for it)
$slack_Channel : The channel where you want the bot to post your stuff
