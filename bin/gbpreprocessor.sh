#!/bin/sh 
#
#  gbpreprocessor.sh
###########################################################################
#
#  Purpose:  This script controls the execution of the
#            genbank/refseq pre-processor load.
#
Usage="Usage: $0"
#
#  Env Vars:
#
#      See the configuration file
#
#  Inputs:
#
#      - Configuration file
#
#  Outputs:
#
#      - An archive file
#      - Log files defined by the environment variables ${LOG_PROC},
#        ${LOG_DIAG}, ${LOG_CUR} and ${LOG_VAL}
#      - ${WORKDIR} files are moved to ${OUTPUTDIR}
#      - Exceptions written to standard error
#      - Configuration and initialization errors are written to a log file
#        for the shell script
#
#  Exit Codes:
#
#      0:  Successful completion
#      1:  Fatal error occurred
#      2:  Non-fatal error occurred
#
#  Assumes:  Nothing
#
#  Implementation:  Description
#
#      - select all pre-processing file that exists for the given file type (ex. GenBank_preprocess)
#      - run the GBRecordSplitter to create one "new" file that contains only mouse records
#      - zip the "new" file
#      - log the "new" file in APP_FileMirrored using non-pre-processing file type (ex. GenBank)
#      - log the pre-processed file into APP_FilesProcessed
#
#  Notes:  None
#
###########################################################################

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
echo '\nGetting files to Pre-Process' | tee -a ${LOG_PROC} ${LOG_DIAG}
APP_INFILES=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh ${RADAR_DBSCHEMADIR} ${JOBSTREAM} ${APP_FILETYPE1} 0`
STAT=$?
checkStatus ${STAT} "getFilesToProcess.csh"
if [ ${STAT} -ne 0 ]
then
    echo "getFilesToProcess.csh failed. Return status: ${STAT}" | tee -a ${LOG_PROC} ${LOG_DIAG}
    exit 1
fi

#
#  Make sure there is at least one pre-processing file to process
#
if [ "${APP_INFILES}" = "" ]
then
    echo "There are no pre-processing files to process" | tee -a ${LOG_PROC} ${LOG_DIAG}
    shutDown
    exit 1
fi

#
# update the split counter for the next available file number to use for the splitter
#     . create the split counter if it does not exist
#
# then, run the splitter
#
echo '\nRunning the splitter' | tee -a ${LOG_PROC} ${LOG_DIAG}
if [ ! -f ${SPLITCOUNTER} ]
then
    splitCounter=1
    echo ${splitCounter} > ${SPLITCOUNTER}
else
    splitCounter=`cat ${SPLITCOUNTER}`
    splitCounter=`expr ${splitCounter} + 1`
    echo ${splitCounter} > ${SPLITCOUNTER}
fi

${APP_CAT1} ${APP_INFILES} | ${DLA_UTILS}/GBRecordSplitter.py -m ${WORKDIR}/${APP_FILETYPE_SPLITTER} ${splitCounter} 
STAT=$?
checkStatus ${STAT} "GBRecordSplitter.py"
if [ ${STAT} -ne 0 ]
then
    echo "GBRecordSplitter.py failed. Return status: ${STAT}" | tee -a ${LOG_PROC} ${LOG_DIAG}
    exit 1
fi

#
# if files have been generated in the work directory
#
#     for each file in the work directory:
# 	    zip the new file
#
#     for each file type, log the zipped-ed file names into RADAR
#
#     move the working files to the output files (their final resting place)
#

echo '\nZipping the new working files' | tee -a ${LOG_PROC} ${LOG_DIAG}
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
            echo "${APP_CAT2} failed. Return status: ${STAT}" | tee -a ${LOG_PROC} ${LOG_DIAG}
	    exit 1
        fi
    done

    #
    # for each file type, log the zipped-ed file names into RADAR
    #
    for fileType in ${APP_FILETYPE2}
    do
        echo '\nLogging the new working files' | tee -a ${LOG_PROC} ${LOG_DIAG}
        ${RADAR_DBUTILS}/bin/logFileToProcessByDir.csh ${RADAR_DBSCHEMADIR} ${WORKDIR} ${OUTPUTDIR} ${fileType}
        STAT=$?
        checkStatus ${STAT} "logFileToProcessByDir.csh"
        if [ ${STAT} -ne 0 ]
        then
            echo "logFileToProcessByDir.csh failed. Return status: ${STAT}" | tee -a ${LOG_PROC} ${LOG_DIAG}
            exit 1
        fi
    done

    #
    # move the working files to the output files (their final resting place)
    #
    mv -f ${WORKDIR}/* ${OUTPUTDIR}

fi

#
# log the processed files
#
echo "Logging processed files ${APP_INFILES}" | tee -a ${LOG_PROC} ${LOG_DIAG}
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

