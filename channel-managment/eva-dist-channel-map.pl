#!/usr/bin/perl -w
use strict;
use Frontier::Client;
use Getopt::Long qw(:config bundling);
use Pod::Usage;
use Term::ReadKey;

#================================================================================================

#Beginning of subroutines block

# logs into the spacewalk server
# returns the client instance handle and the session ID
sub spacewalk_login(\%){
    my $options=shift;
    print_verbose($options,"connecting to \"https://$options->{'hostname'}/rpc/api/\" with username \"$options->{'username'}\"\n");
    my $client = new Frontier::Client(url => "https://$options->{'hostname'}/rpc/api/", debug => 0);
    my $sessionid=$client->call('auth.login',$options->{'username'},$options->{'password'});
    return $client,$sessionid;
}

# logs out of the spacewalk server
sub spacewalk_logout(\%$$){
    my $options=shift;
    my $client = shift;
    my $sessionid=shift;
    print_verbose($options,"Logging out of \"https://$options->{'hostname'}/rpc/api/\"\n");
    $client->call('auth.logout',$sessionid);
    return 1;
}

# verifies that a software channel exists
# if a channel name is specified instead of the label it replaces the contents of $options->{'channel'} with the label for the channel
# returns 1 on success
# returns 0 on failure
sub channel_exists(\%$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $channel_list=$client->call('channel.listSoftwareChannels',$sessionid);
    for my $channel (@{$channel_list}){
	if ($channel->{'label'}=~/^\Q$options->{'channel'}\E$/){
	    print_verbose(%{$options},"confirmed the channel exists by label\n");
	    return 1;
	}
	elsif($channel->{'name'}=~/^\Q$options->{'channel'}\E$/){
	    print_verbose(%{$options},"confirmed the channel exists by name with label \"$channel->{'label'}\"\n");
	    $options->{'channel'}=$channel->{'label'};
	    return 1;
	}
    }
    print_verbose(%{$options},"Could not find a software channel with an name or label that matches \"$options->{'channel'}\"\n");
    return 0;
}

# gets a list of all of the current entries in the default channel map
# it returns an array of hashes on success
sub listmap(\%$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $map=$client->call('distchannel.listDefaultMaps',$sessionid);
    return $map;
}

# sets or updates an entry in the default channel map
sub setmapping(\%$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    $client->call('distchannel.setDefaultMap',$sessionid,$options->{'os'},$options->{'release'},$options->{'arch'},$options->{'channel'});
}

# deletes an exiting entry in the default channel map
sub deletemapping(\%$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    $client->call('distchannel.setDefaultMap',$sessionid,$options->{'os'},$options->{'release'},$options->{'arch'},'');
}

# retrives and prints the current contents of the default channel map
sub printmap(\%$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $map=listmap(%{$options},$client,$sessionid);
    print"----------------------------------------------------------------------------\n";
    printf("|%30s|%24s|%9s|%8s|\n",'         Channel Label        ','    Operating System    ',' Release ','  Arch  ');
    print"|------------------------------|------------------------|---------|--------|\n";
    for my $channel(@{$map}){
	printf("|%30s|%24s|%9s|%8s|\n",$channel->{'channel_label'}, $channel->{'os'}, $channel->{release}, $channel->{arch_name});
	print"|------------------------------|------------------------|---------|--------|\n";
    }
    print"----------------------------------------------------------------------------\n";
}

sub print_help{
    pod2usage(-verbose => 0, -exitval => 'NOEXIT');
}

# A simple print wrapper that only prints when the verbose flag has been set
sub print_verbose(\%$){
    my $options=shift;
    my $string=shift;
    if ($options->{'verbose'}){
	print $string;
    }
}
# End of subroutines block

#================================================================================================

# Beginning of option parsing block
my $options={};
GetOptions(
  'u|username=s'=>\$options->{'username'},
  'H|hostname=s'=>\$options->{'hostname'},
  'p|password=s'=>\$options->{'password'},
  'n|noninteractive'=>\$options->{'noninteractive'},
  'h|help'=>\$options->{'help'},
  'v|verbose'=>\$options->{'verbose'},
  'l|list'=>\$options->{'list'},
  's|set'=>\$options->{'set'},
  'd|delete'=>\$options->{'delete'},
  'c|channel=s'=>\$options->{'channel'},
  'o|os=s'=>\$options->{'os'},
  'r|release=s'=>\$options->{'release'},
  'a|arch=s'=>\$options->{'arch'},
);

#End of option parsing block

#================================================================================================

#Beginning of option validation

my @errors;

if (@ARGV){
    push(@errors," options \"@ARGV\" are invalid\n");
}
# Verifying that all of the required options that determine what the script is suppose to do are present
# If help is specified skip all other validation because it will be ignored any way
unless ($options->{'help'}){
    unless($options->{'username'}){
	if (defined $ENV{'SPACEWALKUSER'}){
	    print_verbose(%{$options},"Setting the username to \"$ENV{'SPACEWALKUSER'}\" from the SPACEWALKUSER environment variable\n");
	    $options->{'username'}=$ENV{'SPACEWALKUSER'};
	}
	#prompting user to enter a username
	else{
	    print "Username:";
	    my $username=<STDIN>;
	    chomp $username;
	    $username=~s/\s+//g;
	    if ($username=~/\w+/){
		$options->{'username'}=$username;
	    }
	    else{
		push(@errors,"ERROR: No username defined\n");
	    }
	}
    }
    unless($options->{'password'}){
	if (defined $ENV{'SPACEWALKPASS'}){
	    print_verbose(%{$options},"Setting the password to the contents of the SPACEWALKPASS environment variable\n");
	    $options->{'password'}=$ENV{'SPACEWALKPASS'};
	}
	else{
	    #prompting the user for their password
	    print "Password:";
	    ReadMode 2;
	    my $password= ReadLine;
	    ReadMode 0;
	    print "\n";
	    chomp $password;
	    $password=~s/\s+//g;
	    if ($password=~/\w+/){
		$options->{'password'}=$password;
	    }
	    else{
		push(@errors,"ERROR: No password defined\n");
	    }
	}
    }
    unless($options->{'hostname'}){
	if (defined $ENV{'SPACEWALKHOST'}){
	    print_verbose(%{$options},"Setting the hostname to \"$ENV{'SPACEWALKHOST'}\" from the SPACEWALKHOST environment variable\n");
	    $options->{'hostname'}=$ENV{'SPACEWALKHOST'};
	}
	else{
	    print_verbose(%{$options},"No hostname specified by command line or environment variable setting to the default \"localhost\"\n");
	    $options->{'hostname'}='localhost';
	}
    }
# Verifying that all of the required options that determine what the script is suppose to do are present
# If help is specified skip all other validation because it will be ignored any way
    # If list is specified make sure set and delete are not
    if ($options->{'list'}){
	if($options->{'set'}){
	    push(@errors,"ERROR: you can not use option --set or -s with --list or -l\n");
	}
	if ($options->{'delete'}){
	    push(@errors,"ERROR: you can not use option --delete or -d with --list or -l\n");
	}
    }
    elsif ($options->{'set'}){
	# If set is specified make sure delete is not
	if ($options->{'delete'}){
	    push(@errors,"ERROR: you can not use option --delete or -d with --set or -s\n");
	}
	# Ensure the "Operating System" name was specified
	unless(defined $options->{'os'} and $options->{'os'}=~/\w+/){
	    push(@errors,"ERROR: Required option -o or --os was not set or set to a null value\n");
	}
	# Ensure the release was specified
	unless(defined $options->{'release'} and $options->{'release'}=~/\w+/){
	    push(@errors,"ERROR: Required option -r or --release was not set or set to a null value\n");
	}
	# Ensure the Architecture name was specified
	unless(defined $options->{'arch'} and $options->{'arch'}=~/\w+/){
	    push(@errors,"ERROR: Required option -a or --arch was not set or set to a null value\n");
	}
	# Ensure the channel name or label was specified
	unless(defined $options->{'channel'} and $options->{'channel'}=~/\w+/){
	    push(@errors,"ERROR: Required option -c or --channel was not set or set to a null value\n");
	}
    }
    elsif($options->{'delete'}){
	unless(defined $options->{'os'} and $options->{'os'}=~/\w+/){
	    push(@errors,"ERROR: Required option -o or --os was not set or set to a null value\n");
	}
	unless(defined $options->{'release'} and $options->{'release'}=~/\w+/){
	    push(@errors,"ERROR: Required option -r or --release was not set or set to a null value\n");
	}
	unless(defined $options->{'arch'} and $options->{'arch'}=~/\w+/){
	    push(@errors,"ERROR: Required option -a or --arch was not set or set to a null value\n");
	}
    }
    else{push(@errors,"ERROR: you must specify an operation list, set, delete, or help")}
}

if (@errors){
    for my $error (@errors){
	warn $error;
	
    }
    print_help();
    die "ERROR: Exiting due to invalid or missing options\n"
}

#End of option validation

#================================================================================================

#Beginning main loop
if ($options->{'help'}){
   print_help();
   exit 0;
}
my ($client , $sessionid) = spacewalk_login(%{$options});
if ($options->{'list'}){
    printmap(%{$options},$client,$sessionid);
}
elsif ($options->{'set'}){
    if (channel_exists(%{$options},$client,$sessionid)){
	setmapping(%{$options},$client,$sessionid);
    }
    else{
	die "ERROR: channel \"$options->{'channel'}\" could not be found in the database\n";
    }
    
}
elsif ($options->{'delete'}){
    my $map=listmap(%{$options},$client,$sessionid);
    my $match=0;
    for my $mapping (@{$map}){
	if ($options->{'os'} =~ /^$mapping->{'os'}$/ and $options->{'release'} =~ /^$mapping->{'release'}$/ and $options->{'arch'} =~ /^$mapping->{'arch_name'}$/){
	    $match++;
	}
    }
    if ($match){
	deletemapping(%{$options},$client,$sessionid);
    }
    else{
	die "ERROR: could not find a match for Operating System \"$options->{'os'}\" Release \"$options->{'release'}\" Architecture \"$options->{'arch'}\"\n";
    }
}

spacewalk_logout(%{$options},$client,$sessionid);
undef $sessionid;

exit 0;

#End of main loop

#================================================================================================

#Beginning END block 

END{
    #resetting the terminal mode just in case some one hits Ctrl-C while the password promot is set to not echo
    ReadMode 0;
    #No orphaned sessions left behind.
    if (defined $sessionid){
	spacewalk_logout(%{$options},$client,$sessionid);
    }
}



#Beginning POD documentation

=head1 NAME

eva-dist-channel-map.pl - Allows you to view and update the default channel map

=head1 SYNOPSIS

 [export SPACEWALKUSER='username']

 [export SPACEWALKPASS='password']

 [export SPACEWALKHOST='hostname.example.org']

 eva-dist-channel-map.pl --list [--username spacewalkuser] \
 [--password spacewalkpassword] [--hostname hostname.example.org]

 eva-dist-channel-map.pl --set --channel channel-label \
 --os some-distro-name --release release-name-or-number --arch x86_64 \
 [--username spacewalkuser] [--password spacewalk password] \
 [--hostname hostname.example.org]

 eva-dist-channel-map.pl --delete --os some-distro-name \
 --release release-name-or-number --arch i386 [--username spacewalkuser] \
 [--password spacewalk password] [--hostname hostname.example.org]


=head1 DESCRIPTION

=over 4

=item spacewalk-dist-channel-map.pl is a simple script to allow you to update the default channel map. The default channel map defines the responses of the spacewalk default channel based on the distribution name and release version and architecture when a host is registered without an activation key that explicitly sets the base channel.

=back

=head1 SUPPORTED ENVIRONMENT VARIABLES

=head2 SPACEWALKUSER

=over 4

=item SPACEWALKUSER can be set to contain the username rather than specifying it on the command line

=back

=head2 SPACEWALKPASS

=over 4

=item SPACEWALKPASS can be set to contain the password for the spacewalk server rather than specifying it on the command line

=back

=head2 SPACEWALKHOST

=over 4

=item SPACEWALKHOST can be set to contain the host name or IP address of the spacewalk server rather than specifying it on the command line

=back

=head1 OPTIONS

=head2 -u spacewalkuser or --username spacewalkuser

=over 4

=item Defines the user name to use to connect to the spacewalk server. This is a required option unless the SPACEWALKUSER environment variable has been set. This option supersedes the contents of the SPACEWALKUSER environment variable.

=back

=head2 -p spacewalkpassword or --password spacewalkpassword

=over 4

=item Defines the password to use on the command line.  This option supersedes the contents of the SPACEWALKPASS environment variable. If you don not specify the password on the command line or in the SPACEWALKPASS environment varriable you will be prompted for it.

=back

=head2 -h hostname.example.org or --hostname hostname.example.org

=over 4

=item Defines the hostname of the spacewalk server. This option supersedes the contents of the SPACEWALKHOST environment variable. If you don not specify the password on the command line or in the SPACEWALKHOST environment varriable it defaults to localhost.

=back

=head2 -l or --list

=over 4

=item lists the current contents of the default distribution channel map.

=back

=head2 -s or --set

=over 4

=item Set or update an entry in the default distribution map. This option requires you to set the channel, operating system, release, and architecture.

=back

=head2 -d or --delete

=over 4

=item delete an entry in the default distribution map. This option requires you to set the operating system, release, and CPU architecture.

=back

=head2 -c channe-label or --channel "Channel Name"

=over 4

=item Sets the channel of the to maping you want to create, or modify. This can be either the label or name of the channel. best practice is to use the label because it reduces the chance of typos on most cases.

=back

=head2 -o distribution-name or --os distribution-name

=over 4

=item Sets the name of the distribution of the to maping you want to create, delete, or modify. if you doubt what the content should be look at the OS: field in the Description of a registered host either in the spacewalk web interface or th the hosts F</etc/sysconfig/rhn/systemid> file.

=back

=head2 -r release-name or --release release-name

=over 4

=item Sets the release name of the mapping you want to create, delete, or modify. If you doubt whet the content should be look at the Release: field in the Description of a registered host either in the spacewalk web interface or in the hosts F</etc/sysconfig/rhn/systemid> file.

=back

=head2 -a cpu_arch or --arch cpu_arch

=over 4

=item Sets the CPU architecture of the mapping you want to create, delete, or modify. If you doubt whet the content should be look at the CPU Arch: field in the Description of a registered host either in the spacewalk web interface or in the hosts F</etc/sysconfig/rhn/systemid> file. 

=back

=head2 -h or --help

=over 4

=item Prints out a brief help and exits.

=head1 LIMITATIONS

=over 4

=item The default distribution map is global at this time so if your server contains multiple organization you should only set ti to channels shared to all of the organizations on the server

=back

=head1 TODO

=item Add more messages to verbose mode.

=item Add more comments in the code to make it easier for people to patch in the future.

=back

=head1 AUTHOR

=over 4

=item Written by Paul Robert Marino

=item Last Modified April 4th 2012

=back

=head1 COPYRIGHT

=over 4

=item Copyright 2012 Paul Robert Marino.  License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>. This is free software: you are free to change and redistribute it.  There is NO WARRANTY, to the extent permitted by law.

=back

=head1 ALSO SEE

=over 4

=item http://docs.redhat.com/docs/en-US/Red_Hat_Network_Satellite/5.4/html/API_Overview/handlers/DistChannelHandler.html

=item http://docs.redhat.com/docs/en-US/Red_Hat_Network_Satellite/5.4/html/Reference_Guide/sect-Reference_Guide-Systems.html#sect-Reference_Guide-Systems-Activation_Keys_mdash_
