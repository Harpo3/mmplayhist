#!/bin/bash
menu_from_array ()
{
select item; do
# Check the selected menu item number
if [ 1 -le "$REPLY" ] && [ "$REPLY" -le $# ];
then
echo "The selected location is $item"
prepend=$item
break;
else
echo "Wrong selection: Select any number from 1-$#"
fi
done
}
set -e
print_help(){
cat << 'EOF'

A kid3-based utility to add a custom TXXX frame for writing LastPlayedDate data directly to tags.
Writes the LastPlayedDate found in the MediaMonkey database to each tag. Requires kid3 and sqlite.
Place a copy of the MM.DB file in the home directory before running this script.

Usage: mmplayhist.sh [option] 

options:
-h display this help file
-n specify TXXX frame name (default: Songs-DB_Custom1)
-q quiet - hide terminal output
-t change tag time format from sql to epoch time (default: sql)

Modifies tags to enable custom playlists by using "LastPlayedDate" history imported from the MediaMonkey database. Tag version required is ID3v2.3.

Using the kid3-cli utility, the utility scans all music files using the directory paths from the MediaMonkey database, and for the frame name identified (default is Songs-DB_Custom1), creates a TXXX frame with that name, then assigns the LastTimePlayed value from the database to each tag. MediaMonkey uses sql time format, but the tag's value format can be converted to epoch time, if specified.

Time to complete varies by processor and can take time for large libraries.

EOF
}
showdisplay=1
framename="Songs-DB_Custom1"
timetype="sql"
mmdb="$HOME/MM.DB"
# Use getops to set any user-assigned options
while getopts ":hn:qt" opt; do
  case $opt in
    h) 
      print_help
      exit 0;;
    n)
      framename=$OPTARG 
      ;;
    q)      
      showdisplay=0 >&2
      ;;
    t)
      timetype="epoch" 
      ;;
    \?)
      printf 'Invalid option: -%s\n' "$OPTARG"
      exit 1
      ;;
    :)
      printf 'Option requires an argument: %s\n' "$OPTARG"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))
bash extractmmdb.sh $showdisplay
mmcsv="$HOME/Songs_MM.DB.csv"
mmcsv2="$HOME/Songs_MM.DB2.csv"
sed -i 's/\://' $mmcsv # remove colon
sed -i 's/\\/\//g' $mmcsv # change backslash to forward slash
mydirpath="$(tail -1 $mmcsv)"
topfolder="$(echo $mydirpath | awk -F"[//]" '{print $2}')"
prepend=""
numdirs=0
printf 'The top directory shown in the MediaMonkey database is: /%s'"$topfolder"
printf '\nIs there a directory or directories above /%s'"$topfolder"
printf ' ([Y]/n)?'
read -r choosetoadd
if [ "$choosetoadd" == "${choosetoadd#[Yn]}" ] 
then
    printf 'Please enter the number of parent directory levels (up to 5) that exist above the %s\n'"$topfolder"
    printf ' folder, so there is a complete path for the database entries (for example,\nif the full directory path is /mnt/files/%s'"$topfolder" 
    printf ', enter 2):\n'
    read numdirs     
    case $numdirs in
    1)
    my_array=( $(dirname /*/"$topfolder") )    
    ;;
    2)
    my_array=( $(dirname /*/*/"$topfolder") )    
    ;;
    3)
    my_array=( $(dirname /*/*/*/"$topfolder") ) 
    ;;
    4)
    my_array=( $(dirname /*/*/*/*/"$topfolder") )
    ;;
    5)
    my_array=( $(dirname /*/*/*/*/*/"$topfolder") )
    ;;
    \?)
    printf 'Invalid option: -%s\n' "$OPTARG"
    exit 1
    ;;
    esac    
    printf "\nSelect parent directory path.\n"
    menu_from_array "${my_array[@]}"
else
    printf "\nSkipping parent directories.\n"
fi
# add prepended path value to beginning of all lines and output to $mmcsv2
awk -F '^' -v prefix="$prepend" '(NR>1) {print prefix $0}' "$mmcsv" > "$mmcsv2"
rm -f "$mmcsv"
# add MediaMonkey value for LastPlayedDate to each tag in library
{
read -r # skip header
while IFS= read -r line; do    
    trackpath="$(echo $line | cut -d '^' -f1)"  # return the file path value
    exists=$(kid3-cli -c "get ""$framename" "$trackpath") # check for existing frame, write if needed
    if [ -z "$exists" ]
    then 
        sudo kid3-cli -c "set TXXX.Description ""$framename" "$trackpath"
    fi   
    mmsqlval="$(echo $line | cut -d '^' -f2)"  # return LastPlayedDate value
    if [ $showdisplay == 1 ]; then echo $trackpath $mmsqlval;fi 
    if [ "$timetype" == "sql" ]
    then        
        sudo kid3-cli -c "set ""$framename"" $mmsqlval" "$trackpath" # write to tag
    fi
    if [ "$timetype" == "epoch" ]
    then # convert sql time to epoch time       
        mmepoch="$(printf "%.0f \n" "$(echo "($mmsqlval-25569)*86400" | bc -l)")"
        sudo kid3-cli -c "set ""$framename"" $mmepoch" "$trackpath" # write to tag
    fi
done } < "$mmcsv2"
if [ $showdisplay == 1 ]; then echo "Finished. Removing exported table $mmcsv and copy of $mmdb";fi
rm -f "$mmcsv2"
rm -f "$mmdb"
