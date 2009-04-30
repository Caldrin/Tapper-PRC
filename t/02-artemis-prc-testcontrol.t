#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;
use File::Temp qw/ :seekable /;


use Artemis::Model 'model';
use Artemis::Schema::TestTools;



use Test::More tests => 12;

my $config_bkup = 't/files/artemis.backup';

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = FATAL, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Artemis::PRC::Testcontrol'); }



my $mock_control = new Test::MockModule('Artemis::PRC::Testcontrol');
$mock_control->mock('nfs_mount', sub { return(0);});

my $mock_prc = new Test::MockModule('Artemis::PRC');
$mock_prc->mock('log_and_exec', sub { return(0);});


my $fh          = File::Temp->new();
my $config_file = $fh->filename;
system("cp",$config_bkup, $config_file) == 0 or die "Can't copy config file:$!";
$ENV{ARTEMIS_CONFIG} = $config_file;

my $server;
my @content;


my $pid=fork();
if ($pid==0) {
        sleep(2); #bad and ugly to prevent race condition

        my $testcontrol = new Artemis::PRC::Testcontrol;
        $testcontrol->run();
        $testcontrol->run();
        exit 0;

} else {
        $server = IO::Socket::INET->new(Listen    => 5,
                                        LocalPort => 1337);
        ok($server, 'create socket');
        eval{
                local $SIG{ALRM}=sub{die("timeout of 5 seconds reached while waiting for reboot test.");};
                alarm(5);
                my $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[0].=$line;
                }

                $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[1].=$line;
                }


                $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[2].=$line;
                }


                alarm(0);
        };
        is($@, '', 'Get status messages in time');
        waitpid($pid,0);

        my @msg = ("prc_number:0,start-testing\n",
                   "prc_number:0,reboot:0,2\n",
                   "prc_number:0,reboot:1,2\n");
        is($content[0], $msg[0], 'Receiving start message');
        is($content[1], $msg[1], 'First reboot message');
        is($content[2], $msg[2], 'Second reboot message');
}

my $config = YAML::Syck::LoadFile($config_file) or die("Can't read config file $config_file: $!");
is ($config->{reboot_counter}, 2, "Writing reboot count back to config");

########################################################
#
# Test status messages for multiple test scripts
#
########################################################

$ENV{ARTEMIS_CONFIG} = "t/files/multitest.conf";

@content=();

$pid=fork();
if ($pid==0) {
        sleep(2); #bad and ugly to prevent race condition

        my $testcontrol = new Artemis::PRC::Testcontrol;
        $testcontrol->run();
        exit 0;

} else {
        eval{
                local $SIG{ALRM}=sub{die("timeout of 5 seconds reached while waiting for multiple test scripts messages.");};
                alarm(5);
                my $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[0].=$line;
                }

                $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[1].=$line;
                }


                $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[2].=$line;
                }

                $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content[3].=$line;
                }


                alarm(0);
        };
        is($@, '', 'Get status messages in time');
        waitpid($pid,0);

        my @msg = ("prc_number:0,start-testing\n",
                   "prc_number:0,testprogram 0,end-testprogram\n",
                   "prc_number:0,testprogram 1,error-testprogram:",
                   "prc_number:0,end-testing\n");
        is(  $content[0],    $msg[0],  'Receiving start message');
        is(  $content[1],    $msg[1],  'First test script message');
        like($content[2], qr($msg[2]), 'Second test script message');
        is(  $content[3],    $msg[3],  'Finished test');
}



