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
my $CONFIGFILE = undef;
my $DEBUG = 0;
my $FFMPEG = "$Bin/ffmpeg";
my $FFMPEG_OPTIONS = ' ';
my $VERBOSE = 0;
my $tmpdir = "/tmp/mp4.$$";
my %imageIndex2duration = ();
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
    /^-h(elp)?$/o && &usage;
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
    # default: config file
    # make sure they haven't already given you one
    $CONFIGFILE = $_;
}

# make sure you got a CONFIGFILE and that it exists
if (! defined $CONFIGFILE) {
    print "!!! ERROR: CONFIGFILE undefined\n";
    &usage;
} elsif (! -f $CONFIGFILE) {
    print "!!! ERROR: $CONFIGFILE does not exist\n";
    &usage;
}

# determine where the configfile is
my $CONFIGFILEDIR = &dirname($CONFIGFILE);
my $CONFIGFILENAME = &basename($CONFIGFILE);

# now split the config file into name and extension
# use the filename part as the project name
(my $projName = $CONFIGFILENAME) =~ s/\..+$//;

#========================================================================
# Main loop
#========================================================================

# pushd into the CONFIGFILE dir
$CONFIGFILEDIR = &pushd($CONFIGFILEDIR);

# parse configfile
my $index = '01';
my ($imageFile, $imageType, $duration) = undef;
my ($audioFile, $audioType) = undef;

open (CFG, "$CONFIGFILENAME") || die $!;
while (<CFG>) {
    # ignore comments and blank lines
    /^#/ && next;
    /^\s+$/ && next;
    # this matches the image entries
    /^((.+?)\.(png|jpg))\,(\d+)\s*$/ && do {
	($imageFile, $imageType, $duration) = ($1, $3, $4);
	# update the hash tables
	$imageIndex2file{$index} = $imageFile;
	# pad duration
	while (length($duration) < 2) {
	    $duration = "0" . $duration;
	}

	$imageIndex2duration{$index} = $duration;
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
    print "!!! ERROR: config file line unrecognized:\n";
    print ">>> $_";
    exit 1;
}
close CFG;

# make sure image files are defined and exist
if (! defined $imageIndex2file{'01'}) {
    print "!!! ERROR: no image files defined!\n";
    exit 1;
} else {
    for my $key (sort keys %imageIndex2file) {
	if (! -f $imageIndex2file{$key}) {
	    print "!!! ERROR: image file does not exist:\n";
	    print ">>> $imageIndex2file{$key}";
	    exit 1;
	}
    }
}
# make sure the audio file is defined and exists
if (! defined $audioFile) {
    print "!!! ERROR: audioFile undefined\n";
    exit 1;
} elsif (! -f $audioFile) {
    print "!!! ERROR: audio file does not exist\n";
    print ">>> $audioFile";
    exit 1;
}

######################################################################
# if we get this far, we have verified the contents of the config file
# :-)
######################################################################

# create tmp dir with timestamped image files
mkdir $tmpdir unless $DEBUG;
# make the initial timestamp 01/01/2000 GMT
my $touchTime = 946684800;
my $touchDate = &etime2date($touchTime);
my $outfile = '00' . '.' . $imageType;

# make the initial 00 image from the first image
print "... Generating screenshot sequence:\n";
print ">>> cp $imageIndex2file{'01'} $tmpdir/$outfile\n";
system "cp $imageIndex2file{'01'} $tmpdir/$outfile" unless $DEBUG;
print ">>> touch -t $touchDate $tmpdir/$outfile\n";
system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;

# now process the rest of the image files
for my $key (sort keys %imageIndex2file) {
    $outfile = $key . '.' . $imageType;
    $touchTime += $imageIndex2duration{$key};
    $touchDate = &etime2date($touchTime);
    print ">>> cp $imageIndex2file{$key} $tmpdir/$outfile\n";
    system "cp $imageIndex2file{$key} $tmpdir/$outfile" unless $DEBUG;
    print ">>> touch -t $touchDate $tmpdir/$outfile\n";
    system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;
}
# copy the audio file to the tmpdir
print "... Copying audio file:\n";
print ">>> cp $audioFile $tmpdir\n";
system "cp $audioFile $tmpdir";
# need this for the ffmpeg command later
my $audioFileName = &basename($audioFile);

# pushd into the tmpdir
&pushd($tmpdir) unless $DEBUG;

# run ffmpeg using the tmpdir files we created above
my $ffmpegCmd = "$FFMPEG -ts_from_file 1 -i %2d.png -i $audioFileName -c:v libx264 $projName.mp4"; 
print "... Executing ffmpeg:\n";
print ">>> $ffmpegCmd\n";
#system "$FFMPEG -ts_from_file 1 -i %2d.png -i $audioFileName -c:v libx264 $projName.mp4" unless $DEBUG;
if (! $DEBUG) {
    open(FFMPEG, "$ffmpegCmd 2>&1 |") || die $!;
    while (<FFMPEG>) {
	print if $VERBOSE;
    }
    close FFMPEG;
}

# make sure a video file was produced
if (! -f "$tmpdir/$projName.mp4") {
    print "!!! ERROR: $projName.mp4 was not created\n";
    print "!!! ERROR: Run with -verbose option for details\n";
    # cleanup end exit with stat = 1
    &cleanUp(1);
} else {
    # mv the mp4 file back to the dir where the config file lives
    print "... Moving $projName.mp4 to $CONFIGFILEDIR\n";
    system ("mv $projName.mp4 $CONFIGFILEDIR") unless $DEBUG;
}

# cleanup end exit with stat = 0
&cleanUp(0);

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


#------------------------------------------------------------------------
sub cleanUp {
#------------------------------------------------------------------------

    my $exitStat = shift;
    # rm tmpdir
    system "rm", "-rf", $tmpdir;
    &popd;
    exit $exitStat;

}

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

#------------------------------------------------------------------------
sub etime2date {
#------------------------------------------------------------------------

    # converts epoch time to real time

    my $time = shift;

    my ($sec,$min,$hour,$day,$month,$year) = (gmtime($time))[0,1,2,3,4,5,6]; 

    # add one to month index
    $month++;

    # pad values with 0's if required
    for my $val (\$sec, \$min, \$hour, \$day, \$month) {
	while(length($$val)<2) {
	    $$val = "0" . $$val;
	}
    }


    my $date = $month.$day.$hour.$min.".".$sec;

    return $date;

} # end: etime2gmtime

