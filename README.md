
# Slideshow from Emails

This is a project originaly from about 2009/2010. Uploaded here as it was getting more 
obscure on my old hosting. I haven't tried running it since then but I can't see any 
reason why it wouldn't still work. The documentation is also taken from an old writup and reworked int GitHub markdown.

I was asked to set up a system to show photographs at a wedding (this can then apply 
to any other type of event). 

The features are:
  * Display a slideshow of images
  * Allow images to be sent to an email address.
  * Copy images into the system by hand (or over a network etc...).
  * Display the email address to send images to.
  * Preferentially have some priority control on images so new ones are shown first.

What I was thinking of doing, was a light weight window manager and using a shell script with the following logic:
  - Check email account, download new messages, extract images and copy to image dir (same image dir can be used to copy files to by hand).
  - Update a database with new images (sqlite for example from shell script).
  - Select image file from database (which contains numbers on times image has been shown) semi random, favouring new images.
  - Handing the file name to an application (`qiv` for example) which will then display that image.
  - Every 5 images (make this a variable) display a nice image saying "send your picture to whatever@email.com"

I decided to use a gmail account for the email address and their for `imap` integration is the easy way to go.

## Post Implementation Notes
  * Process management (backgrounding etc...) is interesting.
  * The email integration was very easy once I found this post: [Script to download attachments from Gmail?](http://ubuntuforums.org/showthread.php?t=931690)
  * I want to do more with parallel processing in bash scripts: [A srcipt for running processes in parallel in Bash](http://pebblesinthesand.wordpress.com/2008/05/22/a-srcipt-for-running-processes-in-parallel-in-bash/)

## The Future
There is always time to come back to a project...
  * Python implementation?
  * MMS reception.
  * SMS reception: 
    * [Party Scroller](http://www.plasma2002.com/partyscroller/)
    * [Receiving Incoming SMS/Text Messages From Google Voice in PHP](http://sudocode.net/article/190/receiving-incoming-smstext-messages-from-google-voice-in-php/)

# Usage

## Requirements

Required aps (configuration required before running script):
  * `feh` - an image viewer
  * `sqlite3` - a light SQL server (easy way to do file I/O even if it is overkill)
  * `offlineimap` - Create offline copy of `IMAP` account
  * `mpack` - Allows extraction of file from `MIME` data in emails

## Setup

My set-up is something like this:
  1. Install the required supporting apps.
  2. Create a `~/mail` dir for the email and configure `offlineimap`.
  3. Create a working directory for the script: `~/photoshow`
  4. Create a directory for the images: `~/photoshow/images`
  5. Create a directory for the script to reside in (I recommend putting lock files here also): `~/photoshow/scripts`
  6. Create a directory for the database to be stored (it can go in with the scripts if you prefer): `~/photoshow/database`
  7. Create a image to display an email address to send pictures to (default location 
  `images/emailAddress.png`)
  8. Configure any of the variables required in the script (they are in the top portion).
  9. Run the script as (folders should be better managed in the script):
```
cd ~/photoshow
scripts/managealbum.sh
```
# The Script
It works now with new features:
  * check if file is image
  * check image rotation

But the checking needs to be better managed as non images are added to database (even if application when going to show them finds they don't exist and their for removes them from DB this is poor program flow! TODO

file: `managealbum.sh`

# How it works

A quick breakdown of how it works as it was an interesting project which does many things.

## Get emails
Thanks to this post: [Script to download attachments from Gmail?](http://ubuntuforums.org/showthread.php?t=931690)

```
#Install offlineimap and mpack
sudo apt-get install offlineimap mpack

#Create a folder ~/mail for storing the Gmail messages
mkdir ~/mail

#Create a text file and save it as ~/.offlineimaprc
emacs ~/.offlineimaprc
```

The file should contain:
```
[general]
accounts = GMail

ui = Noninteractive.Basic

[Account GMail]
localrepository = GMailLocalMaildirRepository
remoterepository = GMailServerRepository

[Repository GMailLocalMaildirRepository]
type = Maildir
localfolders = ~/mail/

[Repository GMailServerRepository]
type = IMAP
remotehost = imap.gmail.com
remoteuser = yourgmailaccount@gmail.com
remotepass = yourgmailpassword
ssl = yes
```

Then execute with commands:
```
#synchronise emails (to get new)
offlineimap 

#extract attachments from emails
munpack /home/<USER>/mail/<LABEL>/new/*

#delete local copies of emails
rm /home/<USER>/mail/<LABEL>/new/*

#synchronise emails (to remove processed emails if you want).
#emails deleted from disk get removed from server at sync
offlineimap 
```
## Add New Images to DB
The database is created using [sqlite](http://www.sqlite.org/)

create a database in a sub directory: `sqlite3 database/album.db`
```
CREATE TABLE pics (file string, timesViewed int, priority int);
```

Some sqlite commands:
```
#add an image to the DB
echo "INSERT INTO pics (file,timesViewed,priority) VALUES ('SDC13516.JPG',0,0);" | sqlite3 database/album.db
#view images in DB
echo "SELECT * FROM pics;" | sqlite3 database/album.db
#TRUNCATE tabel
echo "DELETE FROM pics;" | sqlite3 database/album.db
```

```
for PICFILE in `find -maxdepth 1 -type f | cut -d "/" -f2`; \
do  echo "INSERT INTO pics (file,timesViewed,priority) VALUES ('$PICFILE',0,0);" | sqlite3 database/album.db ; \
    mv $PICFILE images/. ; \
done 


for PICFILE in `find -maxdepth 1 -type f | cut -d "/" -f2`
do 
    echo "INSERT INTO pics (file,timesViewed,priority) VALUES ('$PICFILE',0,0);" | sqlite3 database/album.db
    mv $PICFILE images/.
done 
```

## Select New Images
Select unseen images:
```
echo "SELECT file FROM pics WHERE timesViewed = 0;" | sqlite3 database/album.db
```

Select images with bias on newer ones
```
  SELECT file, 
         substr(random(),3,5)-(timesViewed*10) AS rorder 
    FROM pics
ORDER BY rorder;

SELECT file, substr(random(),3,5)-(timesViewed*10) AS rorder FROM pics ORDER BY rorder;

SELECT file, substr(random(),3,5)-(timesViewed*10) AS rorder FROM pics ORDER BY rorder LIMIT 1;
```


```
#create list of files
echo "SELECT file, substr(random(),3,5)-(timesViewed*10) AS rorder FROM pics ORDER BY rorder LIMIT 1;" \
     | sqlite3 database/album.db \
     | cut -d "|" -f 1
     
     
#cycle images then stop
feh --cycle-once \
    --auto-zoom  \
    --fullscreen \
    --slideshow-delay 2 \
  image1.ext image2.ext emailAddress.png
  
#OR
feh --cycle-once \
    --auto-zoom  \
    --fullscreen \
    --slideshow-delay 2 \
    --filelist images/list.txt  
```

## Process Control
### (Almost) Infinite Loop

In bash scripts infinite loops can be created as such:
```
while [ 1 ]
do
  echo "stuff"
done

while [ TRUE = TRUE ]
do
  echo "stuff"
done
```
Using `Ctrl + C` to stop the process. While in many cases this works a more graceful (and remote controllable) method is to create a "lock" file, its presence controls behaviour. In the below example the loop will continue infinitely until the process is killed or the "lock" file is deleted. This allows for further post processing to take place in the same script once the file has been removed if required.
```
#define file
APPLICATIONLOCKFILE=process.lock

#create file
touch $APPLICATIONLOCKFILE

#loop all the time the file exists:
while [ -e $APPLICATIONLOCKFILE ]
do
  echo "stuff"
done
```

## Sub Processes
Sometimes it is handy for two (or more) processes to run at the same time. In the case of this script it is checking and updating from email while showing the images. There are many ways of having two independent processes running side by side:
  - Manage as two distinct scripts.
  - Implement parallel processing and if required [subshells](http://tldp.org/LDP/abs/html/subshells.html).

My method for parallel processing that I used here allowed the email process to essentially fork and continue until it had finished blocking further executions while the rest of the application continued. It is worth noting that in bash the following variables are very useful in logging/debugging this sort of thing (see [TLDP : Advanced Bash-Scripting Guide : 9.1. Internal Variables](http://tldp.org/LDP/abs/html/internalvariables.html)):
  * `$$` - Process ID (PID) of the script itself.
  * `$BASHPID` - Process ID of the current instance of Bash. This is not the same as the $$ variable, but it often gives the same result.

```
PROCESLOCKFILE=processing.lock

function clearLock(){
    echo "------ clearing lock file: $PROCESLOCKFILE :: $$ : $BASHPID"
    if [ -e $PROCESLOCKFILE ]
    then 
      rm -f $PROCESLOCKFILE
    fi
}

function processingTask(){
    #create the lock
    touch $PROCESLOCKFILE
    
    #perform processing
    echo "Whatever processing required :: $$ : $BASHPID"
    sleep 100
    
    #clear the lock at the end of time consuming process
    clearLock
}


#clear any old lock files before starting
clearLock


#infinite loop
while [ 1 ]
do
    #Other tasks here

    #Prevernt the "processingTask" from running more than once at a time. But allow the rest of the application to continue without blocking.
    if [ -e $PROCESLOCKFILE ]
    then
      echo "------ process locked :: $$ : $BASHPID"
    else
      #The "&" causes this process to fork to a new bash instance but still have the same process ID of the script (Hence $$ and $BASHPID). 
      #Any variable changes in the new bash instance DON'T impact the rest of this sript!
      processingTask &
    fi
    
    #Other tasks here
done
  
```

To control the flow of a script and wait for sub processes to finish before continuing one can use the wait command (from the bash man page):
```
       wait [n ...]
              Wait  for each specified process and return its termination sta-
              tus.  Each n may be a process ID or a job  specification;  if  a
              job  spec  is  given,  all  processes in that jobâs pipeline are
              waited for.  If n is not given, all currently active child  pro-
              cesses  are  waited  for,  and  the return status is zero.  If n
              specifies a non-existent process or job, the  return  status  is
              127.   Otherwise,  the  return  status is the exit status of the
              last process or job waited for.
```