#!/bin/sh
#
#  gbpreprocessor.sh
###########################################################################
#
#  Purpose:  This script controls the execution of the
#            genbank/refseq pre-processor
#
Usage="Usage: $0 configFile"
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
#      - select the files to process from radar (fileType=GenBank_preprocess)
#      - run the GBRecordSplitter to create one "new" file that contains 
# 	    only mouse records
#      - zip the "new" file
#      - log the "new" file in radar for gbseqload (fileType=GenBank)
#      - log the processed files in radar now that we'ver processed them
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
# get the files to process
#

if [ ${APP_RADAR_INPUT} = true ]
then
    echo 'Getting files to process' | tee -a ${LOG_PROC} ${LOG_DIAG}
     # set the input files to empty string
    APP_INFILES=""

    # get input files
    APP_INFILES=`${RADAR_DBUTILS}/bin/getFilesToProcess.csh \
	${RADAR_DBSCHEMADIR}  ${JOBSTREAM} ${APP_FILETYPE1} 0`
    STAT=$?
    checkStatus ${STAT} "getFilesToProcess.csh"

    # if no input files report and shutdown gracefully
    if [ "${APP_INFILES}" = "" ]
    then
        echo "No files to process" | tee -a ${LOG_DIAG} ${LOG_PROC}
        shutDown
        exit 0
    fi

    echo 'Done getting files to Process' | tee -a ${LOG_DIAG}

fi


# if we get here then APP_INFILES not set in configuration this is an error
if [ "${APP_INFILES}" = "" ]
then
    # set STAT for endJobStream.py called from postload in shutDown
    STAT=1
    checkStatus ${STAT} "APP_RADAR_INPUT=${APP_RADAR_INPUT}. \
	SEQ_LOAD_MODE=${SEQ_LOAD_MODE}. \
	Check that APP_INFILES has been configured."

fi

#
# update the counter for the next available file number to use 
# for the record splitter
# create the split counter if it does not exist, then run the splitter
#
echo '' | tee -a ${LOG_PROC} ${LOG_DIAG}
echo 'Running the splitter' | tee -a ${LOG_PROC} ${LOG_DIAG}
if [ ! -f ${SPLITCOUNTER} ]
then
    splitCounter=1
    echo ${splitCounter} > ${SPLITCOUNTER}
else
    splitCounter=`cat ${SPLITCOUNTER}`
    splitCounter=`expr ${splitCounter} + 1`
    echo ${splitCounter} > ${SPLITCOUNTER}
fi

${APP_CAT_METHOD} ${APP_INFILES} | ${PYTHON} ${DLA_UTILS}/GBRecordSplitter.py -r ${RECORD_MAX} \
	-m -v ${WORKDIR}/${APP_FILETYPE_SPLITTER} ${splitCounter} 
STAT=$?
checkStatus ${STAT} "GBRecordSplitter.py"
if [ ${STAT} -ne 0 ]
then
    echo "GBRecordSplitter.py failed. Return status: ${STAT}" | \
	tee -a ${LOG_PROC} ${LOG_DIAG}
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
#     move the zipped file to the output directory (their final resting place)
#

echo '' | tee -a ${LOG_PROC} ${LOG_DIAG}
echo 'Zipping the new working files' | tee -a ${LOG_PROC} ${LOG_DIAG}
checkLS=`ls ${WORKDIR}`
if [ "${checkLS}" != "" ]
then
    for file in ${WORKDIR}/*
    do
        ${APP_ZIP_METHOD} ${file}
        STAT=$?
        checkStatus ${STAT} "${APP_ZIP_METHOD}"

        if [ ${STAT} -ne 0 ]
        then
            echo "${APP_CAT2} failed. Return status: ${STAT}" | \
		tee -a ${LOG_PROC} ${LOG_DIAG}
	    exit 1
        fi
    done

    #
    # for each file type, log the zipped-ed file names into RADAR
    #
    for fileType in ${APP_FILETYPE2}
    do
        echo '' | tee -a ${LOG_PROC} ${LOG_DIAG}
        echo 'Logging the new working files' | tee -a ${LOG_PROC} ${LOG_DIAG}
        ${RADAR_DBUTILS}/bin/logFileToProcessByDir.csh ${RADAR_DBSCHEMADIR} \
	    ${WORKDIR} ${OUTPUTDIR} ${fileType}
        STAT=$?
        checkStatus ${STAT} "logFileToProcessByDir.csh"
        if [ ${STAT} -ne 0 ]
        then
            echo "logFileToProcessByDir.csh failed. Return status: ${STAT}" \
		| tee -a ${LOG_PROC} ${LOG_DIAG}
            exit 1
        fi
    done

    #
    # move the working files to the output files (their final resting place)
    #
    mv -f ${WORKDIR}/* ${OUTPUTDIR}

fi

if [ ${APP_RADAR_INPUT} = true ]
then
    #
    # log the processed files
    #
    echo "" | tee -a ${LOG_PROC} ${LOG_DIAG}
    echo "Logging processed files ${APP_INFILES}" | tee -a ${LOG_PROC} ${LOG_DIAG}
    for file in ${APP_INFILES}
    do
	${RADAR_DBUTILS}/bin/logProcessedFile.csh ${RADAR_DBSCHEMADIR} \
	    ${JOBKEY} ${file} ${APP_FILETYPE1}
	STAT=$?
	checkStatus ${STAT} "logProcessedFile.csh"
    done
fi

#
# run postload cleanup and email logs
#
shutDown

exit 0
