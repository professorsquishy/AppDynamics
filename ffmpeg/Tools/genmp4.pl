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
my $CLEANUP = 1;
my $CONFIGFILE = undef;
my $DEBUG = 0;
my $ERR_STATUS = 0;
my $FADE = 0;
my $FADE_FRAMES = 25;
my $FFMPEG = "$Bin/ffmpeg";
my $FFMPEG_AUDIO_OPTIONS = undef;
my $FFMPEG_CMD = undef;
my $FFMPEG_IMAGE_OPTIONS = '-ts_from_file 1';
my $FFMPEG_OPTIONS = undef;
my $FFMPEG_VIDEO_CRF = 20;
my $FFMPEG_VIDEO_ENCODING = 'libx264';
my $FFMPEG_VIDEO_FPS = 30;
my $FFMPEG_VIDEO_OPTIONS = '-crf ' . $FFMPEG_VIDEO_CRF . ' -r:v ' . $FFMPEG_VIDEO_FPS . ' -profile:v main -level:v 4.0 -pix_fmt yuv420p -c:v ' . $FFMPEG_VIDEO_ENCODING;
my $IMAGE_TYPE = 'jpg';
my $REPAIR_EOL = 1;
my $REPAIR_EOL_ONLY = 0;
my $TOTAL_FRAMES = 0;
my $VERBOSE = 0;
my $VIDEO_DURATION = 0;
my $VIDEO_DURATION = undef;
my $tmpdir = "/tmp/mp4.$$";
my %imageIndex2endTime = ();
my %imageIndex2file = ();
my @CONFIG_ERRORS = ();
my @DIRSTACK = ();

select(STDOUT); $| = 1;     # make unbuffered

#========================================================================
#
# STEP 1.0: Read script input arguments
#
# Read the input arguments to the script to figure out what optional
# beahvior to implement. See usage for details (perl genmp4.pl -h).
#
#========================================================================
while (@ARGV) {
    $_ = shift;
    /^debug=(.+?)$/o && do {
	$DEBUG = $1;
	next;
    };
    /^fade=(.+?)$/o && do {
	$FADE = $1;
	next;
    };
    /^ffmpeg=(.+?)$/o && do {
	$FFMPEG = $1;
	next;
    };
    /^ffmpeg-options=(.+?)$/o && do {
	$FFMPEG_OPTIONS = $1;
	next;
    };
    /^video-options=(.+?)$/o && do {
	# append more video options
	$FFMPEG_VIDEO_OPTIONS .= ' ' . $1;
	next;
    };
    /^image-options=(.+?)$/o && do {
	# prepend more image options
	$FFMPEG_IMAGE_OPTIONS = $1 . ' ' . $FFMPEG_IMAGE_OPTIONS;
	next;
    };
    /^audio-options=(.+?)$/o && do {
	$FFMPEG_AUDIO_OPTIONS = $1;
	next;
    };
    /^example=(.+?)$/o && do {
	$1 && &example;
	next;
    };
    /^verbose=(.+?)$/o && do {
	$VERBOSE = $1;
	next;
    };
    /^cleanup=(.+?)$/o && do {
	$CLEANUP = $1;
	next;
    };
    /^repaireolonly=(.+?)$/o && do {
	$REPAIR_EOL_ONLY = $1;
	next;
    };
    /^repaireol=(.+?)$/o && do {
	$REPAIR_EOL = $1;
	next;
    };
    /^-.*$/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
    /=/ && do {
	print "!!! ERROR: $_: Bad option\n";
	exit 1;
    };
    # default: config file
    # make sure they haven't already given you one
    $CONFIGFILE = $_;
}

#========================================================================
#
# STEP 1.1: Verify script input arguments
#
#========================================================================

# Make sure the ffmpeg executable exists
#
if (! -f $FFMPEG) {
    print "!!! ERROR: $FFMPEG does not exist\n";
    &usage;
}
# initialize $FFMPEG_CMD string
$FFMPEG_CMD = $FFMPEG;

# Make sure that config file exists! if not, print usage and exit
#
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


# pushd into the CONFIGFILE dir
$CONFIGFILEDIR = &pushd($CONFIGFILEDIR);

# if the $REPAIR_EOL_ONLY flag is set, just do that
if ($REPAIR_EOL_ONLY) {
    &fixEolChars($CONFIGFILE);
    exit 0;
}

# set some initial variable values
my $errString = '';
my $index = '01';
my $lineno = 0;
my $numOfImageFiles = 0;
my $numOfImageLines = 0;
my ($audioFile, $audioType) = undef;
my ($imageFile, $imageType, $endTime) = undef;

#========================================================================
#
# STEP 2.0: Process the config file
#
# OK, now we need to read the config file and make sure all the entries
# make sense (e.g. the files listed actually exist, etc.
#
# Here's where we loop through the config file one line at a time and
# gather all the info (image/audio file paths, durations, etc)
#
#========================================================================
open (CFG, "$CONFIGFILENAME") || die $!;
while (<CFG>) {
    $lineno++;
    # keep count of jpg entries
    /\.$IMAGE_TYPE,/ && do {
	$numOfImageLines++;
    };
    # ignore comments and blank lines
    /^#/ && next;
    /^\s+$/ && next;
    # this matches the image entries
    # NOTE: can only process jpg images!
    /^((.+?)\.(\w+?))\,(\d{1,2}\:\d{2})\s*$/ && do {
	($imageFile, $imageType, $endTime) = ($1, $3, $4);
	# make sure it's a jpg image
	if ($imageType ne $IMAGE_TYPE) {
	    $errString = "!!! Line #" . $lineno . ": Unsupported image type: " . $imageType . "\n>>> " . $_;
	    push @CONFIG_ERRORS, $errString;
	    next;
	}
	# update numOfImageFiles
	$numOfImageFiles++;
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
    $errString = "!!! Line #" . $lineno . ": Unrecognized line\n>>> " . $_;
    push @CONFIG_ERRORS, $errString;
}
close CFG;

#========================================================================
#
# STEP 2.2: Verify the config file contents
#
# Now we see if there were any errors when we processed the config file
# (e.g., do the files actually exist?) 
#
#========================================================================
# first, test if there are any errors in the config file syntax
if (@CONFIG_ERRORS) {
    print "!!! ERROR: the following lines in the config file have errors:\n";
    for my $err (@CONFIG_ERRORS) {
	print $err;
    }
    exit 1;
}

# make sure image files are defined and exist
if (! defined $imageIndex2file{'01'}) {
    print "!!! ERROR: no image files defined!\n";
    $ERR_STATUS = 1;
} else {
    for my $key (sort keys %imageIndex2file) {
	if (! -f $imageIndex2file{$key}) {
	    print "!!! ERROR: image file does not exist:\n";
	    print ">>> ", $imageIndex2file{$key}, "\n";
	    $ERR_STATUS = 1;
	}
    }
}

# make sure the number of jpg entries matches the num of image files
# this should catch the MS EOL issues
if ($numOfImageFiles != $numOfImageLines) {
    print "!!! WARNING: numOfImageFiles (", $numOfImageFiles, ') != numOfImageLines (', $numOfImageLines, ")\n";
    print "!!! Could be DOS EOL issues in your config file\n";
    # only repair if $REPAIR_EOL is set
    if ($REPAIR_EOL) {
	&fixEolChars($CONFIGFILE);
	$ERR_STATUS = 1;
    }
}

# make sure the audio file is defined and exists
if (! defined $audioFile) {
    print "!!! ERROR: audioFile undefined\n";
    $ERR_STATUS = 1;
} elsif (! -f $audioFile) {
    print "!!! ERROR: audio file does not exist\n";
    print ">>> ", $audioFile, "\n";
    $ERR_STATUS = 1;
}

# if ERR_STATUS has been set, exit
if ($ERR_STATUS) {
    exit 1;
}

######################################################################
#
# STEP 3.0: Setup the video/audio files for ffmpeg processing
#
# If we get this far, we have verified the contents of the config file
# :-)
# Now we can do the work to create the video!
#
# In order for ffmpeg to create a video made up of multiple images
# with independent durations, we have to be clever. This required
# creating a copy of each image in a separate temporary working 
# directory and giving it a system timestamp offset from a fixed 
# epoch start time. 
#
######################################################################

# create tmp dir with timestamped image files
mkdir $tmpdir unless $DEBUG;
# make the initial timestamp 01/01/2000 GMT
my $startTime = 946684800;
my $imageEndTime = undef;
my $touchDate = &epochTime2date($startTime);
my $outfile = '00' . '.' . $imageType;

# make the initial 00 image from the first image
# this is necessary to "seed" the starting point of the video with
# a "zeroth" image which is a zero duration copy of the first
# image in the sequence
print "... Generating screenshot sequence:\n";
print ">>> cp $imageIndex2file{'01'} $tmpdir/$outfile\n";
system "cp $imageIndex2file{'01'} $tmpdir/$outfile" unless $DEBUG;
print ">>> touch -t $touchDate $tmpdir/$outfile\n";
system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;

# now that we've seeded the initial image, process the rest of the image files
for my $key (sort keys %imageIndex2file) {
    $outfile = $key . '.' . $imageType;
    $imageEndTime = &endTime2seconds($imageIndex2endTime{$key}) + $startTime;
    $touchDate = &epochTime2date($imageEndTime);
    # save the last image end time
    $VIDEO_DURATION = &endTime2seconds($imageIndex2endTime{$key});
    print ">>> cp $imageIndex2file{$key} $tmpdir/$outfile\n";
    system "cp $imageIndex2file{$key} $tmpdir/$outfile" unless $DEBUG;
    print ">>> touch -t $touchDate $tmpdir/$outfile\n";
    system "touch -t $touchDate $tmpdir/$outfile" unless $DEBUG;
}

# calculate the total number of frames
$TOTAL_FRAMES = $VIDEO_DURATION * $FFMPEG_VIDEO_FPS;

# now copy the audio file to the tmpdir
print "... Copying audio file:\n";
print ">>> cp $audioFile $tmpdir\n";
system "cp $audioFile $tmpdir";
# need this for the ffmpeg command later
my $audioFileName = &basename($audioFile);

######################################################################
#
# STEP 3.1: Run ffmpeg over the files in the temp directory
#
# Now we cd into the temp directory where all our timestamped files
# are and call the ffmpeg program to do it's thing.
#
# If everything goes well, we should be left with a mp4 video that
# has the same name as the config file.
#
######################################################################

# Construct the command:

# add any additional options
if (defined $FFMPEG_OPTIONS) {
    $FFMPEG_CMD .= ' ' . $FFMPEG_OPTIONS;
}

# append the image input options
$FFMPEG_CMD .= ' ' . $FFMPEG_IMAGE_OPTIONS;
# add include of audio files
$FFMPEG_CMD .= ' ' . '-i %2d.jpg';

if (defined $FFMPEG_AUDIO_OPTIONS) {
    $FFMPEG_CMD .= ' ' . $FFMPEG_AUDIO_OPTIONS;
}
# add include of audiofile
$FFMPEG_CMD .= ' ' . "-i $audioFileName";
# append the video output options
$FFMPEG_CMD .= ' ' . $FFMPEG_VIDEO_OPTIONS;
# append the video output name
$FFMPEG_CMD .= ' ' . "$projName.mp4"; 

# pushd into the tmpdir
&pushd($tmpdir) unless $DEBUG;

print "... Executing ffmpeg:\n";
print ">>> $FFMPEG_CMD\n";

# if we're not in DEBUG mode, execute the ffmpeg command and move the
# resulting mp4 file back into the config file dir next to the config
# file that created it
if (! $DEBUG) {

    open(FFMPEG, "$FFMPEG_CMD 2>&1 |") || die $!;
    while (<FFMPEG>) {
	print if $VERBOSE;
    }
    close FFMPEG;

    # make sure a video file was produced
    if (! -f "$tmpdir/$projName.mp4") {
	print "!!! ERROR: $projName.mp4 was not created\n";
	print "!!! ERROR: Run with verbose=1 option for details\n";
	# cleanup end exit with stat = 1
	&cleanUp(1);
    }

    if ($FADE) {

	# apply fade-in, fade-out
	my $tmpFile1 = 'fadein.mp4';
	my $fadeOutStart = $TOTAL_FRAMES - $FADE_FRAMES;

	print "... Applying Fade In\n";
	$FFMPEG_CMD = $FFMPEG . ' -i ' . "$projName.mp4" . ' -vf "fade=in:0:' . $FADE_FRAMES . '" -acodec copy ' . "$tmpFile1";
	print "... $FFMPEG_CMD\n";
	open(FFMPEG, "$FFMPEG_CMD 2>&1 |") || die $!;
	while (<FFMPEG>) {
	    print if $VERBOSE;
	}
	close FFMPEG;

	print "... Applying Fade Out\n";
	$FFMPEG_CMD = $FFMPEG . ' -i ' . "$tmpFile1" . ' -vf "fade=out:' . $fadeOutStart . ':' . $FADE_FRAMES . '" -acodec copy ' . "$projName.fade.mp4";
	print "... $FFMPEG_CMD\n";
	open(FFMPEG, "$FFMPEG_CMD 2>&1 |") || die $!;
	while (<FFMPEG>) {
	    print if $VERBOSE;
	}
	close FFMPEG;

    }

    # mv the mp4 file back to the dir where the config file lives
    print "... Moving $projName.mp4 to $CONFIGFILEDIR\n";
    system ("mv $projName.mp4 $CONFIGFILEDIR");
    if (-f "$projName.fade.mp4") {
	print "... Moving $projName.fade.mp4 to $CONFIGFILEDIR\n";
	system ("mv $projName.fade.mp4 $CONFIGFILEDIR");
    }
    print "... Done\n";

}

######################################################################
#
# STEP 4.0: All done! Just cleanup and exit
#
# All code below this point are subroutine used above.
# 
######################################################################

$CLEANUP && &cleanUp(0);

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
  audio-options="..."     # specify additional ffmpeg audio options
  debug=1                 # set DEBUG flag
  example=1               # show config file example
  fade=[0|1]              # apply fade-in/fade-out effect
  ffmpeg-options="..."    # specify additional ffmpeg cmd options
  ffmpeg=<path-to-file>   # specify alternate ffmpeg exec
  image-options="..."     # specify additional ffmpeg image options
  norepaireol=[0|1]       # skip repairing the EOL char issue
  repaireol=[0|1]         # just repair the EOL char issue
  verbose=1               # show more output from ffmpeg
  video-options="..."     # specify additional ffmpeg video options

EOF

   exit 1;

} # end: usage

#------------------------------------------------------------------------
sub example {
#------------------------------------------------------------------------

    print<<"EOF";


Config file lines must be one of the following:

Comments:
--------

"#" at the beginning of the line

Image File: (jpg files only!!!)
----------

<path-to-image-file>,<end-time-in-MM:SS>

e.g.:

../Screenshots-jpg/01-application_dashboard/Intro_APM_demo10.jpg,05:36

Audio File: (mp3 or wav files)
----------

<path-to-audio-file>

e.g.:

../Audio/Intro_to_APM.mp3

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
    print "... Changing dir to $cwd\n";
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
sub endTime2seconds {
#------------------------------------------------------------------------

    # converts MM:SS to seconds

    my $time = shift;

    my ($min, $sec) = split ':', $time;

    return ($min * 60) + $sec;

} # end: endTime2seconds

#------------------------------------------------------------------------
sub epochTime2date {
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

} # end: epochTime2date

#------------------------------------------------------------------------
sub fixEolChars {
#------------------------------------------------------------------------

    # this function will run perl over the file in an attempt to
    # fix it
    my $file = shift;
    my $bakFile = $file . '.bak';

    # need to replace stray \r chars anywhere in the line
    my $regex = 's@\r@\n@g';

    if (! -f $file) {
	print "!!! ERROR: $file does not exist\n";
	exit 1;
    }

    my $cmd = 'perl -pi.bak -e "' . $regex . '" ' . $file;

    # munge the file and save orig into .bak
    print "### Repairing config file (saving original file in: ", $bakFile, ")\n";
    system ($cmd);
    
    # diff the files
    print "### Diffing: ", $file, ' and ', $bakFile, "\n";
    system ("diff", $file, $bakFile);

}
