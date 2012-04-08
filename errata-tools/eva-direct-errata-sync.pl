#!/usr/bin/perl -w
use strict;
use Frontier::Client;
use Getopt::Long qw(:config bundling);
use Pod::Usage;
use Term::ReadKey;
use Data::Dumper;

#================================================================================================

# Author: Paul Robert Marino<prmarino1@gmail.com>
# Created at: April 2 09:00:00 EDT 2012
#
# LICENSE: GPLv3 or higher
#
# Copyright (c) 2012 All rights reserved.
#
# This file is part of Extravehicular-Activity-Admin.
#
# Extravehicular-Activity-Admin is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Extravehicular-Activity-Admin is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Extravehicular-Activity-Admin. If not, see <http://www.gnu.org/licenses/>.

#================================================================================================

my $VERSION='0.0.alpha1';

#Beginning of subroutines block

# logs into the spacewalk server
# returns the client instance handle and the session ID
sub spacewalk_login(\%$){
    my $options=shift;
    my $direction=shift;
    print_verbose($options,"connecting to \"https://$options->{$direction.'_host'}/rpc/api/\" with username \"$options->{$direction.'_user'}\"\n");
    my $client = new Frontier::Client(url => "https://$options->{$direction.'_host'}/rpc/api/", debug => 0);
    my $sessionid=$client->call('auth.login',$options->{$direction.'_user'},$options->{$direction.'_passwd'});
    return $client,$sessionid;
}

# logs out of the spacewalk server
sub spacewalk_logout(\%$$){
    my $options=shift;
    my $client = shift;
    my $sessionid=shift;
    #print_verbose($options,"Logging out of \"https://$options->{'hostname'}/rpc/api/\"\n");
    $client->call('auth.logout',$sessionid);
    return 1;
}

# A simple print wrapper that only prints when the verbose flag has been set
sub print_verbose(\%$){
    my $options=shift;
    my $string=shift;
    if ($options->{'verbose'}){
	print $string;
    }
}

# verifies that a software channel exists
# if a channel name is specified instead of the label it replaces the contents of $options->{'channel'} with the label for the channel
# returns 1 on success
# returns 0 on failure
sub channel_exists(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $direction=shift;
    my $channel_list=$client->call('channel.listSoftwareChannels',$sessionid);
    for my $channel (@{$channel_list}){
	my $label_tag=0;
	my $name_tag=0;
	if (defined $channel->{'label'}){
	    $label_tag='label';
	    $name_tag='name';
	}
	elsif(defined $channel->{'channel_label'}){
	    $label_tag='channel_label';
	    $name_tag='channel_name';
	}
	else{warn "ERROR: Could not identify the channel label or name fields\n";}
	if ($channel->{$label_tag}=~/^\Q$options->{$direction.'_channel'}\E$/){
	    print_verbose(%{$options},"confirmed the channel exists by label\n");
	    return 1;
	}
	elsif($channel->{$name_tag}=~/^\Q$options->{$direction.'_channel'}\E$/){
	    print_verbose(%{$options},"confirmed the channel exists by name with label \"$channel->{$label_tag}\"\n");
	    $options->{'channel'}=$channel->{$label_tag};
	    return 1;
	}
    }
    print_verbose(%{$options},"Could not find a software channel with an name or label that matches \"$options->{'channel'}\"\n");
    return 0;
}

#returns a hash of channels with a boolian flag that determins if they are under the specified base channel
sub mkchannelsynclist(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $direction=shift;
    my $package_channels={};
    my $channel_label=0;
    print_verbose(%{$options},"searching for channel $options->{$direction.'_channel'}\n");
    my $channels = $client->call('channel.listSoftwareChannels',$sessionid);
    if ($channels){
	#print Dumper($channels) . "\n";
    }
    else{print_verbose(%{$options}, "no channels found\n");}
    for my $channel (@{$channels}) {
	my $nametag=0;
	my $labletag=0;
	if (defined $channel->{'label'}){
	    $nametag='name';
	    $labletag='label';
	}
	elsif(defined $channel->{'channel_label'}){
	    $nametag='channel_name';
	    $labletag='channel_label';
	}
	else{
	    return 0;
	    warn "could not construct the label name regex\n";
	}
	if ($options->{$direction.'_channel'}=~/^(\Q$channel->{$nametag}\E|\Q$channel->{$labletag}\E)$/){
	    $channel_label=$channel->{$labletag};
	}
    }
    unless($channel_label){
	warn "could not find the base channel\n";
	return 0;
    }
    else{print_verbose(%{$options},"setting base channel label for $direction to $channel_label\n");}
    for my $channel (@{$channels}) {
	my $parrenttag=0;
	my $labletag=0;
	if (defined $channel->{'label'}){
	    $labletag='label';
	    $parrenttag='parent_label';
	}
	elsif(defined $channel->{'channel_label'}){
	    $labletag='channel_label';
	    $parrenttag='channel_parent_label';
	}
	else{
	    warn "could not construct the label parentlable regex\n";
	    return 0;
	}
	if ($options->{$direction.'_channel'}=~/^(\Q$channel->{$labletag}\E|\Q$channel->{$parrenttag}\E)$/){
	    #print "adding channel $channel->{$labletag}\n";
	    $package_channels->{$channel->{$labletag}}=1;
	}
	else{$package_channels->{$channel->{$labletag}}=0;}
    }
    return $package_channels;
}

# collects a list of erratas that apply to a channel
sub get_erratas(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $channel=shift;
    my $erratas=defined;
    if (defined $options->{'start_date'} and $options->{'start_date'}){
	if (defined $options->{'end_date'} and $options->{'end_date'}){
	    print_verbose(%{$options},"Getting the list of erratas for channel $channel on $options->{'src_host'} published between $options->{'start_date'} and $options->{'end_date'}\n");
	    $erratas = $client->call('channel.software.listErrata',$sessionid,$channel,$options->{'start_date'},$options->{'end_date'});
	}
	else{
	    print_verbose(%{$options},"Getting the list of erratas for channel $channel on $options->{'src_host'} published on or after $options->{'start_date'}\n");
	    $erratas = $client->call('channel.software.listErrata',$sessionid,$channel,$options->{'start_date'});
	}
    }
    else{
	print_verbose(%{$options},"Getting the list of erratas for channel $channel on $options->{'src_host'}\n");
	$erratas = $client->call('channel.software.listErrata',$sessionid,$channel);
    }
    #print Dumper($erratas) . "\n";
    #normalizing rhn names to satellite and spacewalk compatible names this avoids some compatability issues latter
    for my $errata (@{$erratas}){
	if (defined $errata->{'errata_advisory'}){
	    $errata->{'advisory_name'}=$errata->{'errata_advisory'};
	    delete $errata->{'errata_advisory'};
	}
	if (defined $errata->{'errata_issue_date'}){
	    $errata->{'issue_date'}=$errata->{'errata_issue_date'};
	    $errata->{'date'}=$errata->{'errata_issue_date'};
	    delete $errata->{'errata_issue_date'};
	}
	if (defined $errata->{'errata_update_date'}){
	    $errata->{'errata_update_date'}=$errata->{'errata_update_date'};
	    delete $errata->{'errata_update_date'};
	    
	}
	if (defined $errata->{'errata_synopsis'}){
	    $errata->{'advisory_synopsis'}=$errata->{'errata_synopsis'};
	    delete $errata->{'errata_synopsis'};
	}
	if (defined $errata->{'errata_advisory_type'}){
	    $errata->{'advisory_type'}=$errata->{'errata_advisory_type'};
	    delete $errata->{'errata_advisory_type'};
	}
	if (defined $errata->{'errata_last_modified_date'}){
	    $errata->{'update_date'}=$errata->{'errata_last_modified_date'};
	    delete $errata->{'errata_last_modified_date'};
	}
	#print Dumper($erratas) . "\n";
    }
    return $erratas;
}

sub get_errata(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $errara_name=shift;
    print_verbose(%{$options},"Geting details for $errara_name\n");
    my $errata = eval{$client->call('errata.getDetails',$sessionid,$errara_name)};
    unless($errata){
	return 0;
    }
    if (defined $errata->{'errata_issue_date'}){
	$errata->{'issue_date'}=$errata->{'errata_issue_date'};
	delete $errata->{'errata_issue_date'};
    }
    if (defined $errata->{'errata_update_date'}){
	$errata->{'update_date'}=$errata->{'errata_update_date'};
	delete $errata->{'errata_update_date'};
    }
    if (defined $errata->{'errata_last_modified_date'}){
	$errata->{'last_modified_date'}=$errata->{'errata_last_modified_date'};
	delete $errata->{'errata_last_modified_date'};
    }
    if (defined $errata->{'errata_description'}){
	$errata->{'description'}=$errata->{'errata_description'};
	delete $errata->{'errata_description'};
    }
    if (defined $errata->{'errata_synopsis'}){
	$errata->{'synopsis'}=$errata->{'errata_synopsis'};
	delete $errata->{'errata_synopsis'};
    }
    if (defined $errata->{'errata_topic'}){
	$errata->{'topic'}=$errata->{'errata_topic'};
	delete $errata->{'errata_topic'};
    }
    if (defined $errata->{'errata_references'}){
	$errata->{'references'}=$errata->{'errata_references'};
	delete $errata->{'errata_references'};
    }
    if (defined $errata->{'errata_notes'}){
	$errata->{'notes'}=$errata->{'errata_notes'};
	delete $errata->{'errata_notes'};
    }
    if (defined $errata->{'errata_type'}){
	$errata->{'type'}=$errata->{'errata_type'};
	delete $errata->{'errata_type'};
    }
    if (defined $errata->{'errata_severity'}){
	#$errata->{'severity'}=$errata->{'errata_severity'};
	# field exists in RHN but not spacewalk or satellite
	delete $errata->{'errata_severity'};
    }
    #print Dumper($errata) . "\n";
    return $errata;
}

sub get_errata_pkg_list(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $advisory_name=shift;
    my $raw_packages=defined;
    $raw_packages=$client->call('errata.listPackages',$sessionid,$advisory_name);
    my @packages;
    #only grabing the fields I need and throwing out the rest
    # I need name, version, release, and arch_label
    for my $raw_package (@{$raw_packages}){
	my $package={};
	# working around RHN names that may differ from Satellite  and spacewalk names
	if (defined $raw_package->{'name'}){
	    $package->{'name'}=$raw_package->{'name'};
	}
	elsif(defined $raw_package->{'package_name'}){
	    $package->{'name'}=$raw_package->{'package_name'};
	}
	if (defined $raw_package->{'version'}){
	    $package->{'version'}=$raw_package->{'version'};
	}
	elsif(defined $raw_package->{'package_version'}){
	    $package->{'version'}=$raw_package->{'package_version'};
	}
	if (defined $raw_package->{'release'}){
	    $package->{'release'}=$raw_package->{'release'};
	}
	elsif(defined $raw_package->{'package_release'}){
	    $package->{'release'}=$raw_package->{'package_release'};
	}
	if (defined $raw_package->{'arch_label'}){
	    $package->{'arch_label'}=$raw_package->{'arch_label'};
	}
	elsif(defined $raw_package->{'package_arch_label'}){
	    $package->{'arch_label'}=$raw_package->{'package_arch_label'};
	}
	push(@packages,$package);
	#clean up ram
	for my $key (keys %{$raw_package}){
	    delete $raw_package->{$key};
	}
    }
    #print Dumper(@packages) . "\n";
    if (wantarray){
	return @packages;
    }
    else {return \@packages;}
}

sub find_dst_package_channels(\%$$\@$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $src_pkg_list=shift;
    my $dst_map=shift;
    # using hashes to make them uniq in the first place is more efficient
    my $id_hash={};
    my $channnel_hash={};
    for my $package(@{$src_pkg_list}){
	my $matches=$client->call('packages.findByNvrea',$sessionid,$package->{'name'},$package->{'version'},$package->{'release'},'',$package->{'arch_label'});
	for my $match (@{$matches}){
	    # running in eval because its been know to fail from time to time
	    my $details=0;
	    print_verbose(%{$options},"getting details for package $match->{'name'}\n");
	    $details=eval{$client->call('packages.getDetails',$sessionid,$match->{'id'});};
	    # yes this is two different checks to avoid scarry but meaningless warnings 
	    if ($details){
		for my $pkgchannel (@{$details->{'providing_channels'}}){
		    if ($dst_map->{$pkgchannel}){
			$channnel_hash->{$pkgchannel}=1;
			$id_hash->{$details->{'id'}}=1;
		    }
		}
	    }
	}
	if (defined $options->{'rewrite_package_release_from'} and defined $options->{'rewrite_package_release_to'} and $options->{'rewrite_package_release_from'} and $options->{'rewrite_package_release_to'}){
	    my $altrelease=rewrite_package_release(%{$options},$package->{'release'});
	    my $matches=$client->call('packages.findByNvrea',$sessionid,$package->{'name'},$package->{'version'},$altrelease,'',$package->{'arch_label'});
	    for my $match (@{$matches}){
		# running in eval because its been know to fail from time to time
		my $details=0;
		print_verbose(%{$options},"getting details for package $match->{'name'}\n");
		$details=eval{$client->call('packages.getDetails',$sessionid,$match->{'id'});};
		# yes this is two different checks to avoid scarry but meaningless warnings 
		if ($details){
		    for my $pkgchannel (@{$details->{'providing_channels'}}){
			if ($dst_map->{$pkgchannel}){
			    $channnel_hash->{$pkgchannel}=1;
			    $id_hash->{$details->{'id'}}=1;
			}
		    }
		}
	    }
	    
	}
    }
    return $id_hash,$channnel_hash;
}

sub hash_keys_to_array(\%){
    my $hash=shift;
    my @array;
    if (keys %{$hash}){
	push (@array,@{[keys %{$hash}]});
    }
    if (wantarray){
	return @array;
    }
    else {return \@array;}
}

sub map_package_channels(\%$$$$$$){
    my $options=shift;
    my $src_client=shift;
    my $src_sessionid=shift;
    my $dst_client=shift;
    my $dst_sessionid=shift;
    my $advisory_name=shift;
    my $dst_map=shift;
    my @src_package_list=get_errata_pkg_list(%{$options},$src_client,$src_sessionid,$advisory_name);
    #print Dumper(@src_package_list) . "\n";
    my $dst_packages={};
    my $dst_channels={};
    my ($raw_dst_packages,$raw_dst_channels)=find_dst_package_channels(%{$options},$dst_client,$dst_sessionid,@src_package_list,$dst_map);
    for my $key (keys %{$raw_dst_packages}){
	$dst_packages->{$key}=1;
	print_verbose(%{$options}," adding package id $key\n");
    }
    for my $key (keys %{$raw_dst_channels}){
	print_verbose(%{$options},"adding channel to errata $key\n");
	$dst_channels->{$key}=1;
    }
    my $result_channels=hash_keys_to_array(%{$dst_channels});
    my $result_packages=hash_keys_to_array(%{$dst_packages});
    return $result_packages,$result_channels;
}
sub get_key_words(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $advisory_name=shift;
    #my @keywords=eval($client->call('errata.listKeywords',$sessionid,$advisory_name));
    my $keywords=$client->call('errata.listKeywords',$sessionid,$advisory_name);
    if (wantarray){
	return @{$keywords};
    }
    else{return $keywords;}
}
sub get_bugs(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $advisory_name=shift;
    my $bugzilla='';
    if ($options->{bugzilla_url}){
	$bugzilla=$options->{bugzilla_url} . 'show_bug.cgi?id=';
    }
    my $raw_bugs=$client->call('errata.bugzillaFixes',$sessionid,$advisory_name);
    my @bugs;
    for my $key (keys %{$raw_bugs}){
	my $bug={
	    'id'=>$key,
	    'summary'=>$raw_bugs->{$key},
	    'url'=>''
	};
	if ($bugzilla){
	    $bug->{'url'}=$bugzilla . $key;
	}
	push(@bugs,$bug);
    }
    #print "bugs \n" . Dumper(@bugs) . "\n";
    if (wantarray){
	return @bugs;
    }
    else{return \@bugs;}
}

sub get_cves(\%$$$){
    my $options=shift;
    my $client=shift;
    my $sessionid=shift;
    my $advisory_name=shift;
    my $cve=$client->call('errata.listCves',$sessionid,$advisory_name);
    if (wantarray){
	return @{$cve};
    }
    else{return $cve;}
}

sub rewrite_string($$$){
    my $string=shift;
    my $original=shift;
    my $replacment=shift;
    $string=~s/^(.*)$original(.*)$/$1$replacment$2/;
    return $string;
}

sub rewrite_errata_name(\%$){
    my $options=shift;
    my $name=shift;
    my $newname;
    if (defined $options->{'rewrite_errata_name_from'} and defined $options->{'rewrite_errata_name_to'} and $options->{'rewrite_errata_name_from'} and $options->{'rewrite_errata_name_from'}){
	$newname=rewrite_string($name,$options->{'rewrite_errata_name_from'},$options->{'rewrite_errata_name_to'});
    }
    else{
	$newname=$name;
    }
    return $newname;
}

sub rewrite_package_release(\%$){
    my $options=shift;
    my $release=shift;
    my $newrelease;
    if (defined $options->{'rewrite_package_release_from'} and defined $options->{'rewrite_package_release_to'} and $options->{'rewrite_package_release_from'} and $options->{'rewrite_package_release_to'}){
	$newrelease=rewrite_string($release,$options->{'rewrite_package_release_from'},$options->{'rewrite_package_release_to'});
    }
    else{
	$newrelease=$release;
    }
    return $newrelease;
}

sub pad_time($){
    my $orig=shift;
    unless ($orig=~/^\d\d$/){
	$orig= '0' . $orig;
    }
    return $orig;
}

sub get_previous(\%$){
    my $options=shift;
    my $previous=shift;
    my $minute=60;
    my $hour=3600;
    my $day=86400;
    my $week=604800;
    my $month=2678400; # 31 days better safe than sorry
    my $year=31622400; # 365 days plus 1 for leap year
    my $current_time=time;
    if ($previous=~/^(m|minute)$/i){
	$current_time=$current_time - $minute;
    }
    elsif ($previous=~/^(h|hour)$/i){
	$current_time=$current_time - $hour;
    }
    elsif ($previous=~/^(d|day)$/i){
	$current_time=$current_time - $day;
    }
    elsif ($previous=~/^(w|week)$/i){
	$current_time=$current_time - $week;
    }
    elsif ($previous=~/^(m|month)$/i){
	$current_time=$current_time - $month;
    }
    elsif ($previous=~/^(y|year)$/i){
	$current_time=$current_time - $year;
    }
    else{
	return 0;
    }
    my @time=localtime($current_time);
    my $old_year=$time[5]+1900;
    my $previousdate=pad_time($time[4]) .  pad_time($time[3]) . $old_year . ' ' . pad_time($time[2]) . ':' . pad_time($time[1]) . ':' . pad_time($time[0]);
    return $previousdate;
}

sub auto_sync_erratas(\%$$$$\%\%;$$){
    my $options=shift;
    my $src_client=shift;
    my $src_sessionid=shift;
    my $dst_client=shift;
    my $dst_sessionid=shift;
    my $src_map=shift;
    my $dst_map=shift;
    my $begin_date=shift;
    my $end_date=shift;
    my $duplicate={};
    for my $channel (keys %{$src_map}){
	#print "found rhn channel $channel status $src_map->{$channel}\n";
	if ($src_map->{$channel}){
	    my $src_erratas=get_erratas(%{$options},$src_client,$src_sessionid,$channel);
	    for my $errata (@{$src_erratas}){
		# skiping duplicates in the list which occur if an errata applies to multiple channels on the source host
		unless(defined $duplicate->{$errata->{'advisory_name'}}){
		    $duplicate->{$errata->{'advisory_name'}}=1;
		    print_verbose(%{$options},"checking if $errata->{'advisory_name'} exists on the destination host\n");
		    #print Dumper($errata) . "\n";
		    
		    if (get_errata(%{$options},$dst_client,$dst_sessionid,rewrite_errata_name(%{$options},$errata->{'advisory_name'}))){
			print_verbose(%{$options},"Skipping errata $errata->{'advisory_name'} because it's already in the destination host\n");
		    }
		    else{
			print_verbose(%{$options},"getting $errata->{'advisory_name'} from the source\n");
			my $errata_details=get_errata(%{$options},$src_client,$src_sessionid,$errata->{'advisory_name'});
			my ($packages,$channels)=map_package_channels(%{$options},$src_client,$src_sessionid,$dst_client,$dst_sessionid,$errata->{'advisory_name'},$dst_map);
			if (defined ${$packages}[0] and defined ${$channels}[0]){
			    $errata_details->{'packageId'}=$packages;
			    $errata_details->{'channelLabel'}=$channels;
			    $errata_details->{'keyword'}=get_key_words(%{$options},$src_client,$src_sessionid,$errata->{'advisory_name'});
			    $errata_details->{'bug'}=get_bugs(%{$options},$src_client,$src_sessionid,$errata->{'advisory_name'});
			    $errata_details->{'cve'}=get_cves(%{$options},$src_client,$src_sessionid,$errata->{'advisory_name'});
			    #print Dumper($errata_details) . "\n";
			    my $new_errata_details={
				'synopsis'=>$errata_details->{'synopsis'},
				'advisory_name'=>rewrite_errata_name(%{$options},$errata->{'advisory_name'}),
				'advisory_release'=>1,
				'advisory_type'=>$errata_details->{'type'},
				'product'=>'Unknown',
				'topic'=>$errata_details->{'topic'},
				'description'=>$errata_details->{'topic'},
				'references'=>$errata_details->{'references'},
				'notes'=>$errata_details->{'notes'},
				'solution'=>'UPDATE'
			    
			    };
			    my $publication=eval{$dst_client->call('errata.create',$dst_sessionid,$new_errata_details,$errata_details->{'bug'},$errata_details->{'keyword'},$errata_details->{'packageId'},'1',$errata_details->{'channelLabel'});};
			    if (defined $publication and defined $publication->{'id'}){
				print "published $new_errata_details->{'advisory_name'} successfully\n";
				if (@{$errata_details->{'cve'}}){
				    if ($dst_client->call('errata.setDetails',$dst_sessionid,$new_errata_details->{'advisory_name'},{'cves'=>$errata_details->{'cve'}})){
					warn "failed to post the CVE's for $new_errata_details->{'advisory_name'}\n";
				    }
				    else{
					print_verbose(%{$options},"posted CVEs for $new_errata_details->{'advisory_name'}\n");
				    }
				}
				else{print_verbose(%{$options},"no CVE's to post $new_errata_details->{'advisory_name'}\n");}
			    }
			    else{warn "ERROR: Failed to post $new_errata_details->{'advisory_name'}\n";}
			    #cleaning up ram
			    for my $key (keys %{$new_errata_details}){
				delete $new_errata_details->{$key};
			    }
			}
			else {print_verbose(%{$options},"Skipping errata $errata->{'advisory_name'} because non of its packages could be found in the destination channels\n");}
			#cleaning up ram
			for my $key (keys %{$errata_details}){
			    delete $errata_details->{$key};
			}
		    
		    }
		}
		else{
		    print_verbose(%{$options},"Found duplicate entry for errata $errata->{'advisory_name'} skipping\n");
		}
		#cleaning up ram
		for my $key (keys %{$errata}){
		    delete $errata->{$key};
		    
		}
	    }
	}
    }

}

# End of subroutines block

#================================================================================================

# Beginning of option parsing block

my $options={};

GetOptions(
    'u|sourceuser=s'=>\$options->{'src_user'},
    'U|destinationuser=s'=>\$options->{'dst_user'},
    's|sourceserver'=>\$options->{'src_host'},
    'S|destinationserver'=>\$options->{'dst_host'},
    'p|sourcepassword=s'=>\$options->{'src_passwd'},
    'P|destinationpassword=s'=>\$options->{'dst_passwd'},
    'c|sourcechannel=s'=>\$options->{'src_channel'},
    'C|destinationchannel=s'=>\$options->{'dst_channel'},
    'r|recursive'=>\$options->{'recursive'},
    'n|dryrun'=>\$options->{'dryrun'},
    'h|help'=>\$options->{'help'},
    'v|verbose'=>\$options->{'verbose'},
    'b|bugzillaurl=s'=>\$options->{'bugzilla_url'},
    'e|rewriteerratanamefrom=s'=>\$options->{'rewrite_errata_name_from'},
    'E|rewriteerratanameto=s'=>\$options->{'rewrite_errata_name_to'},
    'rewritepackagereleasefrom=s'=>\$options->{'rewrite_package_release_from'},
    'rewritepackagereleaseto=s'=>\$options->{'rewrite_package_release_to'},
    'd|startdate=s'=>\$options->{'start_date'},
    'D|enddate=s'=>\$options->{'end_date'},
    'F|startfromprevious=s'=>\$options->{'start_from_previous'},
    'j|loadjobconfig=s'=>\$options->{'batch_config'},
    'J|writejobconfig=s'=>\$options->{'write_config'},
);



#End of option parsing block

#================================================================================================

#Beginning of option validation

my @errors;

if (@ARGV){
    push(@errors," options \"@ARGV\" are invalid\n");
}
unless ($options->{'help'}){
    unless ($options->{'src_user'}){
	if (defined $ENV{'ERRATASRCUSER'}){
	    print_verbose(%{$options},"Setting the source username to \"$ENV{'ERRATASRCUSER'}\" from the ERRATASRCUSER environment variable\n");
	    $options->{'src_user'}=$ENV{'ERRATASRCUSER'};
	}
	else{
	    print "Source Username:";
	    my $username=<STDIN>;
	    chomp $username;
	    $username=~s/\s+//g;
	    if ($username=~/\w+/){
		$options->{'src_user'}=$username;
	    }
	    else{
		push(@errors,"ERROR: No source username defined\n");
	    }
	}
    }
    unless ($options->{'dst_user'}){
	if (defined $ENV{'ERRATADSTUSER'}){
	    print_verbose(%{$options},"Setting the destination username to \"$ENV{'ERRATADSTUSER'}\" from the ERRATADSTUSER environment variable\n");
	    $options->{'dst_user'}=$ENV{'ERRATADSTUSER'};
	}
	else{
	    print "Destination Username:";
	    my $username=<STDIN>;
	    chomp $username;
	    $username=~s/\s+//g;
	    if ($username=~/\w+/){
		$options->{'dst_user'}=$username;
	    }
	    else{
		push(@errors,"ERROR: No destination username defined\n");
	    }
	}
    }
    unless($options->{'src_passwd'}){
	if (defined $ENV{'ERRATASRCPASS'}){
	    print_verbose(%{$options},"Setting the source password to the contents of the ERRATASRCPASS environment variable\n");
	    $options->{'src_passwd'}=$ENV{'ERRATASRCPASS'};
	}
	else{
	    #prompting the user for their password
	    print "Source Password:";
	    ReadMode 2;
	    my $password= ReadLine;
	    ReadMode 0;
	    print "\n";
	    chomp $password;
	    $password=~s/\s+//g;
	    if ($password=~/\w+/){
		$options->{'src_passwd'}=$password;
	    }
	    else{
		push(@errors,"ERROR: No source password defined\n");
	    }
	}
    }
    unless($options->{'dst_passwd'}){
	if (defined $ENV{'ERRATADSTPASS'}){
	    print_verbose(%{$options},"Setting the destination password to the contents of the ERRATADSTPASS environment variable\n");
	    $options->{'dst_passwd'}=$ENV{'ERRATADSTPASS'};
	}
	else{
	    #prompting the user for their password
	    print "Destination Password:";
	    ReadMode 2;
	    my $password= ReadLine;
	    ReadMode 0;
	    print "\n";
	    chomp $password;
	    $password=~s/\s+//g;
	    if ($password=~/\w+/){
		$options->{'dst_passwd'}=$password;
	    }
	    else{
		push(@errors,"ERROR: No destination password defined\n");
	    }
	}
    }
    unless($options->{'src_host'}){
	if (defined $ENV{'ERRATASCR'}){
	    print_verbose(%{$options},"Setting the source server to \"$ENV{'ERRATASCR'}\" from the ERRATASCR environment variable\n");
	    $options->{'src_host'}=$ENV{'ERRATASCR'};
	}
	else{
	    print_verbose(%{$options},"No source server specified by command line or environment variable setting to the default \"rhn.redhat.com\"\n");
	    $options->{'src_host'}='rhn.redhat.com';
	}
    }
    unless($options->{'dst_host'}){
	if (defined $ENV{'ERRATADST'}){
	    print_verbose(%{$options},"Setting the server to \"$ENV{'ERRATADST'}\" from the ERRATADST environment variable\n");
	    $options->{'dst_host'}=$ENV{'ERRATADST'};
	}
	else{
	    print_verbose(%{$options},"No server specified by command line or environment variable setting to the default \"localhost\"\n");
	    $options->{'dst_host'}='localhost';
	}
    }
    unless($options->{'src_channel'}){
	push(@errors,"ERROR: No source channel defined\n");
    }
    unless($options->{'dst_channel'}){
	push(@errors,"ERROR: No destination channel defined\n");
    }
    unless($options->{'bugzilla_url'}){
	print_verbose(%{$options},"No bugzilla url specified setting to the default \"https://bugzilla.redhat.com/\"\n");
    }
    if ($options->{'start_from_previous'}){
	if ($options->{'start_date'}){
	    warn "WARNING: both the start date \"$options->{'start_date'}\" and start from previous \"start_from_previous\" options were specified\n";
	    warn "WARNING: ignoring the start from previous option using the start date \"$options->{'start_date'}\" option st the start date"
	}
	else{
	    $options->{'start_date'}=get_previous(%{$options},$options->{'start_from_previous'})
	}
    }
}



#End of option validation

#================================================================================================

#Beginning main loop

my ($src_client, $src_session) = spacewalk_login(%{$options},'src');

my ($dst_client, $dst_session) = spacewalk_login(%{$options},'dst');

my $src_map=mkchannelsynclist(%{$options},$src_client,$src_session,'src');

my $dst_map=mkchannelsynclist(%{$options},$dst_client,$dst_session,'dst');

auto_sync_erratas(%{$options},$src_client,$src_session,$dst_client,$dst_session,%{$src_map},%{$dst_map});

spacewalk_logout(%{$options},$src_client,$src_session);

undef $src_session;

spacewalk_logout(%{$options},$dst_client,$dst_session);

undef $dst_session;

exit 0;

#End main loop

#================================================================================================

#Beginning end Block


END{
    # Ensuring that nomatter what the script has logged out of the source server cleanly
    if (defined $src_session){
	spacewalk_logout(%{$options},$src_client,$src_session);
    }
    # Ensuring that nomatter what the script has logged out of the destination server cleanly
    if (defined $dst_session){
	spacewalk_logout(%{$options},$dst_client,$dst_session);
    }
}

#End end block

#================================================================================================
