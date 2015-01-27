#!/usr/bin/perl -w
# $Id$

# if no arguments, pring usage
@ARGV || &usage;

use strict;
use warnings;

use File::Basename;
our $CMDDIRNAME = &dirname($0);

use FindBin qw($Bin);       # where was script installed?

# assumes that this script and the ffmpeg executable are in the 
# same directory
my $DEBUG = 0;
my $FOUND_IMAGEFILE = 0;
my $FOUND_MATCH = 0;
my $SCRIPT_REPORT = 0;
my $VERBOSE = 0;
my $searchString = undef;
my %image2script = ();
my @CFG_FILE_LIST = ();

select(STDOUT); $| = 1;     # make unbuffered

#========================================================================
# parse input args
#========================================================================
while (@ARGV) {
    $_ = shift;
    /^-d(ebug)?$/o && do {
	$DEBUG = 1;
	next;
    };
    /^-v(erbose)?$/o && do {
	$VERBOSE = 1;
	next;
    };
    /^-find$/o && do {
	$searchString = shift;
	next;
    };
    /-script-report$/o && do {
	$SCRIPT_REPORT = 1;
	next;
    };
    /^-h(elp)?$/o && &usage;
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
    # assume any other args are config files
    /^(.+?\.config)$/ && do {
	push @CFG_FILE_LIST, $1;
	next;
    };
    
}

if ($SCRIPT_REPORT) {
    # don't need a searchString
    # make sure that there's only 1 cfgfile arg
    if (scalar(@CFG_FILE_LIST) != 1) {
	print "!!! ERROR: -script-report requires exactly ONE config file argument\n";
	exit 1;
    }
} elsif (! defined $searchString) {
    print "!!! ERROR: no search string defined\n";
    &usage;
}

#========================================================================
# Main loop
#========================================================================

# assume that this is run in the current working dir
my $dir = '.';

# if no config files are given as args, run against all of them
if (! defined $CFG_FILE_LIST[0]) {
    @CFG_FILE_LIST = glob "$dir/*.config";
}

# if we didn't find any *.config files, print error and exit
if (! defined $CFG_FILE_LIST[0]) {
    print "!!! ERROR: no *.config files found\n";
    exit 1;
}

for my $configFile (@CFG_FILE_LIST) {

    print "... Processing: ", $configFile, "\n" if $VERBOSE;

    # parse configfile
    my $imageFile = undef;
    my $audioFile = undef;
    my $lineno = 0;
    my $READ_SCRIPT = 0;

    open (CFGFILE, "$configFile") || die $!;
    while (my $line = <CFGFILE>) {
	$lineno++;
	# this matches the image entries
	# NOTE: can only process jpg images!
	$line =~ /^((.+?)\.(\w+?))\,(\d{1,2}\:\d{2})\s*$/ && do {
	    $imageFile = $1;
	    $FOUND_IMAGEFILE = 1;
	    # update the hash tables
	    next;
	};
	# this matches the audio file entries
	$line =~ /^((.+?)\.(mp3|wav))\s*$/ && do {
	    $audioFile = $1;
	    next;
	};
	# default: add text to imageFile's script
	if (defined $imageFile) {
	    # concatenate config file and image file
	    # into one key
	    my $key = $configFile . ':' . $imageFile;
	    push @{$image2script{$key}}, $line;
	}
    }
    close CFGFILE;
}

# if we didn't find any image files in the *.config files,
# tell them that too!
if (! $FOUND_IMAGEFILE) {
    print "!!! ERROR: no image files found in the *.config files\n";
    exit 1;
}

if ($SCRIPT_REPORT) {
    # just print the scripts
    for my $key (sort keys %image2script) {
	for my $line (@{$image2script{$key}}) {
	    # remove "#"
	    $line =~ s/^#//g;
	    print $line;
	}
	print "\n";
    }
    exit 0;
}

# now look for the search string across all the files
for my $key (sort keys %image2script) {
    if ($key =~ /$searchString/) {
	$FOUND_MATCH = 1;
	print "@@@ $key:\n";
	for my $line (@{$image2script{$key}}) {
	    print $line;
	}
	print "\n";
    }
}

# if we didn't find any matches, tell them that too!
if (! $FOUND_MATCH) {
    print "!!! WARNING: no image files matched\n";
    exit 1;
}

#========================================================================
# Subroutines
#========================================================================

#------------------------------------------------------------------------
sub usage {
#------------------------------------------------------------------------

    print<<"EOF";

USAGE: $0 [options]

  Option:                 Description:
  ---------               ----------------------------------------------
  -find '<search-string>' # find <search-string> in all *.config files
  -script-report <file>   # just print out the script for one config file
  -verbose                # print more feedback


Output looks like:

@@@ <config-file-name>:<image-file>:
<script>

e.g.:

@@@ Intro_to_APM2.config:../Screenshots/Intro_to_APM/Slide19.jpg:
#AppDynamics provides deep visibility into your production systems so that you can drill down quickly to the source of the problem, even in complex, distributed#We hope that this short video was informative to you and made you excited about implementing the tool to manage your applications.

EOF

   exit 1;

} # end: usage
