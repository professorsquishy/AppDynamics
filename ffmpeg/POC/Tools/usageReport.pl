#!/usr/bin/perl -w
# $Id$

# if no arguments, pring usage
#@ARGV || &usage;

use strict;
use warnings;

use File::Basename;
our $CMDDIRNAME = &dirname($0);

use FindBin qw($Bin);       # where was script installed?

# assumes that this script and the ffmpeg executable are in the 
# same directory
my $searchString = undef;
my $DEBUG = 0;
my $VERBOSE = 0;
my %imageIndex2endTime = ();
my %imageIndex2file = ();
my @DIRSTACK = ();

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
	$searchString = 0;
	next;
    };
    /^-h(elp)?$/o && &usage;
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
}

#========================================================================
# Main loop
#========================================================================

my $dir = '.';

# parse configfile
my $index = '01';
my ($imageFile, $imageType, $endTime) = undef;
my ($audioFile, $audioType) = undef;
my $lineno = 0;

# get all *.config files in current dir on down
opendir (DIR, $dir) or die $!;
while (my $file = readdir(DIR)) {
    $file =~ /\.config$/ || next;
    print $file, "\n";
    open (CFGFILE, "$file") || die $!;
    while (<CFGFILE>) {
	$lineno++;
	# ignore comments and blank lines
	/^#/ && next;
	/^\s+$/ && next;
	# this matches the image entries
	# NOTE: can only process jpg images!
	/^((.+?)\.(\w+?))\,(\d{1,2}\:\d{2})\s*$/ && do {
	    ($imageFile, $imageType, $endTime) = ($1, $3, $4);
	    # make sure it's a jpg image
	    if ($imageType ne 'jpg') {
		print "!!! ERROR: line $lineno: image type: ", $imageType, " not supported\n";
		exit 1;
	    }
	    # update the hash tables
	    $imageIndex2file{$index} = $imageFile;
	    $imageIndex2endTime{$index} = $endTime;
	    # increment the index
	    $index++;
	    next;
	};
	# this matches the audio file entries
	/^((.+?)\.(mp3|wav))\s*$/ && do {
	    ($audioFile, $audioType) = ($1, $2);
	    next;
	};
	# catch all:
	# if we get here, there's some sort of syntax error
	print "!!! ERROR: line $lineno: config file line unrecognized:\n";
	print ">>> $_";
	exit 1;
    }
    close CFGFILE;
}
close DIR;

#========================================================================
# Subroutines
#========================================================================

#------------------------------------------------------------------------
sub usage {
#------------------------------------------------------------------------

    print<<"EOF";

USAGE: $0 [options] <config-file>

  Option:                 Description:
  ---------               ----------------------------------------------
  -d(ebug)                # set DEBUG flag
  -h(elp)?                # displays usage
  -v(erbose)              # show more output from ffmpeg

EOF

   exit 1;

} # end: usage

#---------------------------------------------------------------------
sub pushd {
#---------------------------------------------------------------------

    my($dir) = shift;
    my($cwd) = '';

    -d "$dir"
        || die "!!! ERROR: pushd: $dir doesn't exist";

    chop($cwd = `pwd`);
    push(@DIRSTACK, "$cwd");

    chdir "$dir"
        || die "!!! ERROR: pushd: Can't pushd $dir";

    #return the full dir path
    chop($cwd = `pwd`);
    print ">>> Changing dir to $cwd\n";
    return "$cwd";

} # end: pushd

#---------------------------------------------------------------------
sub popd {
#---------------------------------------------------------------------

    @DIRSTACK
        || die "!!! ERROR: popd: Directory stack empty";

    my($dir) = pop(@DIRSTACK);

    -d "$dir"
        || die "!!! ERROR: popd: $dir doesn't exist";
    chdir "$dir"
        || die "!!! ERROR: popd: Can't popd $dir";

    return "$dir";

} # end: popd


