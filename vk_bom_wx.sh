#!/bin/bash
# 20171203
# This script is used to broadcast VK weather information on an Allstar node.
# This script downloads web content of current weather observations (based on state) 
# and, based on the input of Location (as $1) to the script, the observations will be 
# isolated using the 'getdata' function.

# There are two other functions in the script - wx_tts and wx_female
#
# wx_tts assembles a text file and a text-to-speech (tts) engine (at this stage, espeak) then generates
# a 'wav' file, then converted to a 'ul' file for tx by asterisk.
#
# wx_female uses the data, using prepared ulaw files, to generate a 'ul' file for tx by asterisk.
# The ul files were prepared from text files, and converted to mp3, using 'texttospeech.com
# using an American female voice.

# Still more work to be done - error trapping, other states
# possibly, converting 'get_temp_vk' to Asterisk as well.
#

###### Assumes that sox and espeak are already installed

# ---- Script variables
Location=$1
#webpage=$2
wkgdir="/tmp"
#
#Location="Ulladulla" # Use as test subject
webpage="http://www.bom.gov.au/vic/observations/vicall.shtml?ref=hdr"
#webpage="http://www.bom.gov.au/nsw/observations/nswall.shtml?ref=hdr"

echo "Getting weather data"
etext=`elinks -dump -dump-width 200 $webpage | grep -i "$Location"`
#text=`lynx -dump -dont_wrap_pre $webpage | grep -i "$Location"`
#links -dump -width 120 $webpage > wx_dump
echo ".......done!"
#---------------------------------------------------------------------
## Check location
#i
#---------------------------------------------------------------------

function get_elinks_data() {
print=$1
datetime=`echo $etext | cut -d "|" -f3`
h=`echo $datetime | cut -c 4-5`
hr=`echo $h | sed 's/^0//'` 

m=`echo $datetime | cut -c 7-8`
min=`echo $m | sed 's/^0//'`

ampm=`echo $datetime | cut -c 9-10`
temp=`echo $etext | cut -d "|" -f4`
rel_h=`echo $etext | cut -d "|" -f7`
wind_dir=`echo $etext | cut -d "|" -f9`
wind_sp=`echo $etext | cut -d "|" -f10`
wind_gust=`echo $etext | cut -d "|" -f11`
press=`echo $etext | cut -d "|" -f14`
#------Print out the data if needed - need lower case 'y' as input to function, otherwise no output - useful for troubleshooting.
if [ $print == "y" ] ; then
  echo "Loc: $Location"
  echo "Time: $hr:$min $ampm"
  echo "Temp: $temp deg."
  echo "RH = $rel_h %"
  echo "Wind: $wind_sp km/h from $wind_dir gusting to $wind_gust km/h"
  echo "Pressure: $press hPa"
fi
#exit 1
}

#--------------------------------------------------------------
# uses espeak to generate 'wav' from text, & sox to convert to 'ul'
function wx_tts() {
print=$1

TM=$(date "+%l %M %p")
echo "Assembling report"
echo "At $hr $min $ampm, the temperature at $Location was $temp degrees Celsius." >> $wkgdir/wx.txt
echo "The relative humidity was $rel_h per cent. The wind was" >> $wkgdir/wx.txt

wd=`echo -n "${wind_dir//[[:space:]]/}"` ## designed to remove any space in string 
case $wd in
        CALM)     echo -n "calm.  " >> $wkgdir/wx.txt ;;
        N)        echo -n "from the North at " >> $wkgdir/wx.txt ;;
        NNE)      echo -n "from the North North East at " >> $wkgdir/wx.txt ;;
        NE)       echo -n "from the North East at " >> $wkgdir/wx.txt ;;
        ENE)      echo -n "from the East North East at " >> $wkgdir/wx.txt ;;
        E)        echo -n "from the East at" >> $wkgdir/wx.txt ;;
        ESE)      echo -n "from the East South East at " >> $wkgdir/wx.txt ;;
        SE)       echo -n "from the South East at " >> $wkgdir/wx.txt ;;
        SSE)      echo -n "from the South South East at " >> $wkgdir/wx.txt ;;
        S)        echo -n "from the South at " >> $wkgdir/wx.txt ;;
        SSW)      echo -n "from the South south west at " >> $wkgdir/wx.txt ;;
        SW)       echo -n "from the South west at " >> $wkgdir/wx.txt ;;
        WSW)      echo -n "from the West south west at " >> $wkgdir/wx.txt ;;
        W)        echo -n "from the West at " >> $wkgdir/wx.txt ;;
        WNW)      echo -n "from the West north west at " >> $wkgdir/wx.txt ;;
        NW)       echo -n "from the North west at " >> $wkgdir/wx.txt ;;
        NNW)      echo -n "from the North north west at " >> $wkgdir/wx.txt ;;
esac

if [ $wind_sp != "CALM" ] ; then
  echo -n $wind_sp" kelometers an hour. " >> $wkgdir/wx.txt            
else
  echo "calm. " >> $wkgdir/wx.txt
fi

g_flag=`echo -n "{wind_gust//[[:space:]]/"`
if [ $g_flag == "-" ] ; then
  echo "** -> No wind gust reading was available"
else 
  echo ", gusting to $wind_gust kelometers per hour. " >> $wkgdir/wx.txt
fi

pflag=`echo -n "${press//[[:space:]]/}"`
if [ $pflag == "-" ] ; then
    echo "** -> No barometric pressure reading was available"
else
    echo "The pressure was $press hecktowpaskals." >> $wkgdir/wx.txt
fi
echo "The present time is $TM." >> $wkgdir/wx.txt
echo ""

if [ $print == "y" ] ; then
  cat $wkgdir/wx.txt
fi

#----- Create audio and tx
#cp node-id-emma.ul $wkgdir/node-id-emma.ul
#echo "creating audio files"
espeak -f $wkgdir/wx.txt -w $wkgdir/wx.wav &> /dev/null 2>&1
sox --temp $wkgdir -V $wkgdir/wx.wav -r 8000 -c 1 -t ul $wkgdir/wx.ul &> /dev/null 2>&1
#echo "      and broadcasting"
echo "tx'ing wx files"
asterisk -rx "rpt localplay 27183 $wkgdir/wx"
asterisk -rx "rpt localplay 27183 $wkgdir/node-id-emma"

rm -f $wkgdir/wx.*
} #----------------------------------------------------------------

function wx_ulaw () {
#-------------------------------------------------------------------------------------------------------
# uses prepared 'ul' files to generate a composite 'ul' file for tx by Asterisk

AUDIO="/etc/asterisk/local/ugwx"

MIN_FLAG=`echo $temp | wc -m`
if [ "$MIN_FLAG" -gt "2" ] ; then
  MINUS=`echo $temp | awk '{ if ( $0 ~/-/ ) print "true" ; else print "false" }'`
fi

# Split the temp into degrees and points of a degree
#
TEMP_P=`echo $temp | tr "." " " | awk '{ print $1}' | tr -d "-"`
TPOINT=`echo $temp | tr "." " " | awk '{ print $2 }'`

echo $Location >> $wkgdir/loc.txt
espeak -f $wkgdir/loc.txt -w $wkgdir/loc.wav &> /dev/null 2>&1
sox --temp $wkgdir -V $wkgdir/loc.wav -r 8000 -c 1 -t ul $wkgdir/loc.ul &> /dev/null 2>&1

cat  $AUDIO/at.ul $AUDIO/$hr.ul $AUDIO/$min.ul $AUDIO/$ampm.ul $AUDIO/in.ul $wkgdir/loc.ul >> $wkgdir/wx.ul
if [ "$MINUS" = "true" ] ; then
  cat $AUDIO/temperature.ul $AUDIO/minus.ul $AUDIO/$TEMP_P.ul $AUDIO/point.ul $AUDIO/$TPOINT.ul $AUDIO/degrees.ul >> $wkgdir/wx.ul
else
  cat $AUDIO/temperature.ul $AUDIO/$TEMP_P.ul $AUDIO/point.ul $AUDIO/$TPOINT.ul $AUDIO/degrees.ul >> $wkgdir/wx.ul
fi

rh=`echo -n "${rel_h//[[:space:]]/}"`
cat $AUDIO/rel_humid.ul $AUDIO/$rh.ul $AUDIO/pct.ul >> $wkgdir/wx.ul

pflag=`echo -n "${press//[[:space:]]/}"`
if [ $pflag == "-" ] ; then
    echo "** -> No barometric pressure reading was available"
else
  echo $press >> $wkgdir/press.txt
  espeak -f $wkgdir/press.txt -w $wkgdir/press.wav &> /dev/null 2>&1
  sox --temp $wkgdir -V $wkgdir/press.wav -r 8000 -c 1 -t ul $wkgdir/press.ul &> /dev/null 2>&1
  cat  $AUDIO/the_pressure_was.ul $wkgdir/press.ul $AUDIO/hpa.ul >> $wkgdir/wx.ul
fi

# Wind Inf
WINDSP_P=`echo $wind_sp | tr "." " " | awk '{ print $1}' | tr -d "-"`
#WINDSP_POINT=`echo $wind_sp | tr "." " " | awk '{ print $2 }'`
if [ "$wind_sp" = "CALM" ] ; then
    cat $AUDIO/calm_wind.ul >> $wkgdir/wx.ul
else
    cat $AUDIO/wind_blowing_speed_of.ul $AUDIO/$WINDSP_P.ul $AUDIO/kph.ul $AUDIO/from_the.ul >> $wkgdir/wx.ul
    wd=`echo -n "${wind_dir//[[:space:]]/}"` ## designed to remove any space in string 
    case $wd in
        N)   cat $AUDIO/north.ul >> $wkgdir/wx.ul ;;
        NNE) cat $AUDIO/north.ul $AUDIO/north.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;
        NE)  cat $AUDIO/north.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;
        ENE) cat $AUDIO/east.ul $AUDIO/north.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;

        E)   cat $AUDIO/east.ul >> $wkgdir/wx.ul ;;
        ESE) cat $AUDIO/east.ul $AUDIO/south.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;
        SE)  cat $AUDIO/south.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;
        SSE) cat $AUDIO/south.ul $AUDIO/south.ul $AUDIO/east.ul >> $wkgdir/wx.ul ;;

        S)   cat $AUDIO/south.ul >> $wkgdir/wx.ul ;;
        SSW) cat $AUDIO/south.ul $AUDIO/south.ul $AUDIO/west.ul>> $wkgdir/wx.ul ;;
        SW)  cat $AUDIO/south.ul $AUDIO/west.ul>> $wkgdir/wx.ul ;;
        SSW) cat $AUDIO/west AUDIO/south.ul $AUDIO/west.ul>> $wkgdir/wx.ul ;;

        W)   cat $AUDIO/west.ul >> $wkgdir/wx.ul ;;
        WNW) cat $AUDIO/west.ul $AUDIO/north.ul  $AUDIO/west.ul >> $wkgdir/wx.ul ;;
        NW)  cat $AUDIO/north.ul  $AUDIO/west.ul >> $wkgdir/wx.ul ;;
        NNW) cat $AUDIO/north.ul $AUDIO/north.ul  $AUDIO/west.ul >> $wkgdir/wx.ul ;;
    esac
#        cat $AUDIO/wind_gusts_upto.ul  $AUDIO/kph.ul
fi

cp $AUDIO/node-id-emma.ul $wkgdir/node-id-emma.ul
#cat $AUDIO/node-id-emma.ul >> $wkgdir/wx.ul

echo "tx'ing wx data"
asterisk -rx "rpt localplay 27183 $wkgdir/wx"
asterisk -rx "rpt localplay 27183 $wkgdir/node-id-emma"

rm -f $wkgdir/loc.*
rm -f $wkgdir/wx.ul
rm -f $wkgdir/press.*
rm -f $wkgdir/rh.*
}

#---------------Main---------------------------
get_elinks_data y

wx_tts n

#wx_ulaw

exit 0

