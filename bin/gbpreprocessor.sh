#!/bin/sh 

#
#  Set up a log file for the shell script in case there is an error
#  during configuration and initialization.
#
#  select all pre-processing file that exists for the given file type (ex. GenBank_preprocess)
#  run the GBRecordSplitter to create one "new" file that contains only mouse records
#  zip the "new" file
#  log the "new" file in APP_FileMirrored using non-pre-processing file type (ex. GenBank)
#  log the pre-processed file into APP_FilesProcessed
#
#

cd `dirname $0`/..
LOG=`pwd`/gbpreprocessor.log
rm -f ${LOG}

#
#  Verify the argument(s) to the shell script.
#
if [ $# -ne 1 ]
then
    echo ${Usage} | tee -a ${LOG}
    exit 1
fi

#
#  Establish the configuration file names.
#
CONFIG_LOAD=`pwd`/$1
CONFIG_LOAD_COMMON=`pwd`/gb_common.config

#
#  Make sure the configuration files are readable.
#

if [ ! -r ${CONFIG_LOAD} ]
then
    echo "Cannot read configuration file: ${CONFIG_LOAD}" | tee -a ${LOG}
    exit 1
fi

if [ ! -r ${CONFIG_LOAD_COMMON} ]
then
    echo "Cannot read configuration file: ${CONFIG_LOAD_COMMON}" | tee -a ${LOG}
    exit 1
fi

#
# Source the load configuration files - order is important
#
. ${CONFIG_LOAD_COMMON}
. ${CONFIG_LOAD}

#
#  Make sure the master configuration file is readable
#

if [ ! -r ${CONFIG_MASTER} ]
then
    echo "Cannot read configuration file: ${CONFIG_MASTER}"
    exit 1
fi

#
#  Source the DLA library functions.
#
if [ "${DLAJOBSTREAMFUNC}" != "" ]
then
    if [ -r ${DLAJOBSTREAMFUNC} ]
    then
        . ${DLAJOBSTREAMFUNC}
    else
        echo "Cannot source DLA functions script: ${DLAJOBSTREAMFUNC}"
        exit 1
    fi
else
    echo "Environment variable DLAJOBSTREAMFUNC has not been defined."
fi

##################################################################
##################################################################
#
# main
#
##################################################################
##################################################################

#
# createArchive including WORKDIR, startLog, getConfigEnv, get job key
#
preload ${WORKDIR}

#
# rm all files/dirs from WORKDIR
#
cleanDir ${WORKDIR}

#
# get the pre-processing files
#
echo '\nGetting files to Pre-Process' | tee -a ${LOG_PROC}
APP_INFILES=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh ${RADAR_DBSCHEMADIR} ${JOBSTREAM} ${APP_FILETYPE1} 0`
STAT=$?
checkStatus ${STAT} "getFilesToProcess.csh"
if [ ${STAT} -ne 0 ]
then
    echo "getFilesToProcess.csh failed. Return status: ${STAT}" | tee -a ${LOG_PROC}
    exit 1
fi

#
#  Make sure there is at least one pre-processing file to process
#
if [ "${APP_INFILES}" = "" ]
then
    echo "There are no pre-processing files to process" | tee -a ${LOG_PROC}
    shutDown
    exit 1
fi

#
# set a split counter for the next available file name to use
# run the splitter
#
echo '\nRunning the splitter' | tee -a ${LOG_PROC}
splitCounter=0
checkLS=`ls ${OUTPUTDIR}`
if [ "${checkLS}" != "" ]
then
    for file in ${OUTPUTDIR}/*.gz
    do
        splitCounter=`echo ${file} | cut -d"." -f2`
    done
    splitCounter=`expr ${splitCounter} + 1`
else
    splitCounter=1
fi

${APP_CAT1} ${APP_INFILES} | ${DLA_UTILS}/GBRecordSplitter.py -m ${WORKDIR}/${APP_FILETYPE2} ${splitCounter} 
STAT=$?
checkStatus ${STAT} "GBRecordSplitter.py"
if [ ${STAT} -ne 0 ]
then
    echo "GBRecordSplitter.py failed. Return status: ${STAT}" | tee -a ${LOG_PROC}
    exit 1
fi

#
# if files have been generated in the work directory
#
#     for each file in the work directory:
# 	    zip the new file
#
#     log the new files in the work directory
#     copy new files to the output directory
#
#     move the working files to the output files (their final resting place)
#

echo '\nZipping the new working files' | tee -a ${LOG_PROC}
checkLS=`ls ${WORKDIR}`
if [ "${checkLS}" != "" ]
then
    for file in ${WORKDIR}/*
    do
        ${APP_CAT2} ${file}
        STAT=$?
        checkStatus ${STAT} "${APP_CAT2}"

        if [ ${STAT} -ne 0 ]
        then
            echo "${APP_CAT2} failed. Return status: ${STAT}" | tee -a ${LOG_PROC}
	    exit 1
        fi
    done

    #
    # log the new files in the work directory
    # copy new files to the output directory
    #
    echo '\nLogging the new working files' | tee -a ${LOG_PROC}
    ${RADAR_DBUTILS}/bin/logPreMirroredFiles.csh ${RADAR_DBSCHEMADIR} ${WORKDIR} ${OUTPUTDIR} ${APP_FILETYPE2}
    STAT=$?
    checkStatus ${STAT} "logPreMirroredFiles.csh"
    if [ ${STAT} -ne 0 ]
    then
        echo "logPreMirroredFiles.csh failed. Return status: ${STAT}" | tee -a ${LOG_PROC}
        exit 1
    fi

    #
    # move the working files to the output files (their final resting place)
    #
    mv -f ${WORKDIR}/* ${OUTPUTDIR}

fi

#
# log the processed files
#
echo "Logging processed files ${APP_INFILES}" | tee -a ${LOG_PROC}
for file in ${APP_INFILES}
do
    ${RADAR_DBUTILS}/bin/logProcessedFile.csh ${RADAR_DBSCHEMADIR} ${JOBKEY} ${file} ${APP_FILETYPE1}
    STAT=$?
    checkStatus ${STAT} "logProcessedFile.csh"
done

#
# run postload cleanup and email logs
#
shutDown

exit 0

