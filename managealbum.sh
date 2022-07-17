#!/bin/bash
##############################################
#
# Script To manage a prioritised slide show 
# of images sent to an email address 
# automatically updating with new images and
# prioritising images that have been shown 
# fewer times (while still having an order 
# which is fairly random)
#
# David Halliday
# https://github.com/d-roman-halliday/photo_slideshow_from_email
#
##############################################
 
 
##############################################
##############################################
# Variables
##############################################
##############################################
 
##############################################
# Application configuration
##############################################
#Number of (old) images to include in each cycle (new images are all added to the next cycle as soon as they are imported)
IMAGELISTSIZE=5
#number of seconds to display each image
IMAGEDURATION=10
 
#For the ordering of images: a 'random number' of length <RANDOMNUMBERLENGTH> is added to <timesViewed> multiplied by <TIMESMULTIPLIER> then sorted ascending
TIMESMULTIPLIER=100
RANDOMNUMBERLENGTH=4
 
##############################################
# Application control
##############################################
#EMAILSTORE=~/mail/<LABEL>/new
EMAILSTORE=~/mail/INBOX/new/
EMAILSTOREBACKUP=~/mail/INBOX/cur
DBFILE=database/album.db
IMAGELIST=images/list.txt
EMAILIMAGE=images/emailAddress.png
DISCARDEDFILELOCATION=images/discardedFileLocation
 
APPLICATIONLOCKFILE=scripts/album.lock
EMAILPROCESLOCKFILE=scripts/emailprocessing.lock
LISTBUILDPROCESLOCKFILE=scripts/imagelist.lock
 
 
##############################################
##############################################
# Supporting functions
##############################################
##############################################
 
function enclose(){
    #for a standard separater in the logs
    echo "=========================================="
}
 
function clearDb(){
    #Mostly for any debugging testing etc...
    enclose
    echo "Blanking the database of images"
    echo "DELETE FROM pics;" | sqlite3 $DBFILE
    enclose
}
 
function checkForDb(){
    enclose
    echo "Checking for db file"
    if [ -e $DBFILE ]
    then 
      echo "DB file exists: $DBFILE"
    else
      echo "CREATE TABLE pics (file string, timesViewed int, priority int);" | sqlite3 $DBFILE
    fi
}
 
function clearEmailLock(){
    echo "------ clearing email lock file: $EMAILPROCESLOCKFILE :: $$ : $BASHPID"
    if [ -e $EMAILPROCESLOCKFILE ]
    then 
      rm -f $EMAILPROCESLOCKFILE
    fi
}
 
function clearImageListLock(){
    echo "~~~~~~ clearing image list lock file: $LISTBUILDPROCESLOCKFILE :: $$ : $BASHPID"
    if [ -e $LISTBUILDPROCESLOCKFILE ]
    then 
      rm -f $LISTBUILDPROCESLOCKFILE
    fi
}
 
function getEmails(){
    enclose
    echo "------ Getting latest emails from IMAP server :: $$ : $BASHPID"
 
    #get emails & delete old ones
    offlineimap
 
    #extract pics - if statement checks for number of files in dir NOT = 0 (I.E. dir not empty)
    if [ $(ls -1A $EMAILSTORE | wc -l) -ne 0 ]
    then
      echo "------ Extracting any attachments from emails in: $EMAILSTORE :: $$ : $BASHPID"
      munpack $EMAILSTORE/*
    fi
 
    #archive/clean up emails - if statement checks for number of files in dir NOT = 0 (I.E. dir not empty)
    if [ $(ls -1A $EMAILSTORE | wc -l) -ne 0 ]
    then
      #delete local copies of emails
      #rm $EMAILSTORE/*
      echo "------ Archiving emails in IMAP server :: $$ : $BASHPID"
      mv $EMAILSTORE/* $EMAILSTOREBACKUP/.
    else
      echo "------ No emails to archive: $EMAILSTORE :: $$ : $BASHPID"
    fi
}
 
function checkIsImageFile(){
  #Return Codes:
  # 0 - file exists and is image file
  # 1 - No Argument handed to function
  # 2 - file not found
  # 3 - file found but not image file

  if [ -z $1 ]
  then
    echo "------ No file handed to checkIsImageFile :: $$ : $BASHPID"
    return 1
  fi

  #file -ib

  if [ -e $1 ]
  then
    COUNTIMAGE=`file -ib $1 | grep -c "image"`

    if [ $COUNTIMAGE == "1" ]
    then
      echo "------ File is image: $1"
      return 0
    else
      echo "------ File is NOT image: $1"
      return 3
    fi
  else
    echo "------ File not found: $1 :: $$ : $BASHPID"
    return 2
  fi
}

function checkCorrectImageRotation() {
#Code From: http://www.stokebloke.com/bash/index.php
#Exif rotation info: http://www.impulseadventure.com/photo/exif-orientation.html
 
  if [ -z $1 ]
  then
    echo "------ No image file handed to checkCorrectImageRotation :: $$ : $BASHPID"
    return
  fi
 
  if [ -e $1 ]
  then
    export orientation=`identify -format "%[EXIF:Orientation]" "$1"`
    echo "------ checkCorrectImageRotation: $1 $orientation :: $$ : $BASHPID"

    #if no orientation is returned (EXIF data not exists)
    if [ -z $orientation ]
    then
      echo "------ No orientation information in image file: $1 :: $$ : $BASHPID"
      return
    fi
 
    if [ $orientation == 1 ]
    then
      echo "------ Image file $1 is already correct rotation"
    elif [ $orientation == 6 ]
    then
      echo "------ Image file $1 is 6 rotating"
      convert -rotate 90 -quality 100 "$1" "$1"
    elif [ $orientation == 8 ]
    then
      echo "------ Image file $1 is 8 rotating"
      convert -rotate -90 -quality 100 "$1" "$1"
    else
      echo "------ Image file $1 has orientation I don't know what to do with: $orientation"
    fi
  else
    echo "------ Image file not found: $1 :: $$ : $BASHPID"
    return
  fi
}
 
function importNewPics(){
    enclose
    echo "------ Importing Latest Pictures to the database & imge dir :: $$ : $BASHPID"
 
    TMPFILE=tmp.txt    
    find -maxdepth 1 -type f \
         | cut -d "/" -f2    \
         | grep -v $TMPFILE  \
         > $TMPFILE
 
    #The biggest problem that this solves is file names with spaces (and other problem characters).
    while read PICFILE
    do
      echo "------ Processing image: $PICFILE"

      #Check File is image
      checkIsImageFile "$PICFILE"

      IMAGESTATUS=$?
      if [ $IMAGESTATUS == "0" ] 
      then
        #rename removing any non standard characters (except '.' for file extensions)
        NEWFILE=`echo $PICFILE | sed -e s/[^A-Za-z0-9.]//g`
 
        #check for duplicate name
        while [ -e images/$NEWFILE ]
        do
          #echo "File exists: $NEWFILE"
          #generate random int
          RANDOMINT=`echo $((RANDOM%10+0))`
          #prepends file name with that random int. Better than having file like: 11111111111111111picture.jpg  
          NEWFILE=$RANDOMINT$NEWFILE
        done
        #insert into db
        echo "INSERT INTO pics (file,timesViewed,priority) VALUES ('$NEWFILE',0,0);" | sqlite3 $DBFILE
        #move image to images/
        mv "$PICFILE" images/$NEWFILE

        #Check that the rotation of the image is correct. feh does not understand exif rotation:
        checkCorrectImageRotation images/$NEWFILE
      else
        #move out non image file
        mkdir -p $DISCARDEDFILELOCATION
        mv "$PICFILE" $DISCARDEDFILELOCATION/.
      fi

    done < $TMPFILE
 
    rm $TMPFILE
    chmod a+r images/*
    echo "------ Importing Latest Pictures to the database & imge dir finished :: $$ : $BASHPID"
}
 
function rebuildImageList(){
    echo "~~~~~~ Rebuilding image list for next cycle : START :: $$ : $BASHPID"
    #lock this process
    touch $LISTBUILDPROCESLOCKFILE
 
    if [ -e $IMAGELIST ]
    then
      rm $IMAGELIST
    fi
 
    #Add existing images to the list
    for FILE in `echo "SELECT file, substr(random(),3,$RANDOMNUMBERLENGTH)+(timesViewed*$TIMESMULTIPLIER) AS rorder FROM pics WHERE timesViewed > 0 ORDER BY rorder ASC LIMIT $IMAGELISTSIZE;" \
                 | sqlite3 $DBFILE \
                 | cut -d "|" -f 1`
    do
       if [ -e images/$FILE ]
       then
         echo "images/$FILE" >> $IMAGELIST
         echo "UPDATE pics SET timesViewed = timesViewed+1 WHERE file = '$FILE';" | sqlite3 $DBFILE
       else
         echo "~~~~~~ Image not found on disk, removing from DB: $FILE : START :: $$ : $BASHPID"
         echo "DELETE FROM pics WHERE file = '$FILE';" | sqlite3 $DBFILE
       fi
    done
 
    #Add NEW (not seen before) images to the list, no limit.
    for FILE in `echo "SELECT file, substr(random(),3,5) AS rorder FROM pics WHERE timesViewed = 0 ORDER BY rorder ASC;" \
                 | sqlite3 $DBFILE \
                 | cut -d "|" -f 1`
    do
       if [ -e images/$FILE ]
       then
         echo "images/$FILE" >> $IMAGELIST
         echo "UPDATE pics SET timesViewed = timesViewed+1 WHERE file = '$FILE';" | sqlite3 $DBFILE
       else
         echo "~~~~~~ Image not found on disk, removing from DB: $FILE : START :: $$ : $BASHPID"
         echo "DELETE FROM pics WHERE file = '$FILE';" | sqlite3 $DBFILE
       fi
    done
 
    #unlock this process
    clearImageListLock
    echo "~~~~~~ Rebuilding image list for next cycle : COMPLETE :: $$ : $BASHPID"
}
 
function showImageList(){
    echo "++++++ Showing images :: $$ : $BASHPID"
    feh --cycle-once \
        --auto-zoom  \
        --fullscreen \
        --slideshow-delay $IMAGEDURATION \
        --filelist $IMAGELIST 
}
 
function showEmailImage(){
    echo "++++++ Showing Email image :: $$ : $BASHPID"
    feh --cycle-once \
        --auto-zoom  \
        --fullscreen \
        --slideshow-delay $IMAGEDURATION \
          $EMAILIMAGE
}
 
function manageImageImport(){
    enclose
    echo "------ Import Emails Cycle : START :: $$ : $BASHPID"
    enclose
 
    getEmails
    importNewPics
    sleep 60
    clearEmailLock
 
    enclose
    echo "------ Import Emails Cycle : COMPLETE :: $$ : $BASHPID"
    enclose
}
 
 
##############################################
##############################################
# Application flow/process
##############################################
##############################################
 
checkForDb
clearEmailLock
clearImageListLock
 
#clearDb
 
#Test that the email image $EMAILIMAGE file exists
if [ -e $EMAILIMAGE ]
then
  echo "Email Address image found: $EMAILIMAGE"
else
  echo "Email Address image not found: $EMAILIMAGE"
  exit 1
fi
 
#Create lock file for application loop
enclose
touch $APPLICATIONLOCKFILE
echo "To stop execution at end of next cycle remove file: $APPLICATIONLOCKFILE"
enclose
 
#Infinite loop so programm runs continuous. Loop stops when lock file removed
while [ -e $APPLICATIONLOCKFILE ]
do
    enclose
    echo "++++++ Process Cycle : START :: $$ : $BASHPID"
    enclose
 
    #Prevernt the import from running more than once at a time since this part gets looped over.
    if [ -e $EMAILPROCESLOCKFILE ]
    then
      echo "------ Email import process locked"
    else
      touch $EMAILPROCESLOCKFILE
      manageImageImport &
    fi
 
    #Prevernt the import from running more than once at a time since this part gets looped over.
    if [ -e $LISTBUILDPROCESLOCKFILE ]
    then
      echo "~~~~~~ List build process locked"
    else
      rebuildImageList &
    fi
 
    #sleep 10
    showEmailImage
 
    #Show images as long as the text file containing the list exists
    if [ -e $IMAGELIST ]
    then
      #echo showing images
      #cat -n $IMAGELIST
      showImageList
    fi
 
    #echo "++++++ Sleeping to debug"
    #sleep 100
    enclose
    echo "++++++ Process Cycle : COMPLETE :: $$ : $BASHPID"
    enclose

done
 
exit 0
