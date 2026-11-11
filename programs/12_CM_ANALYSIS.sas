
/***********************************************************************
 PROGRAM: 12_CM_ANALYSIS.sas
 PURPOSE:
   1. Derive analysis-ready concomitant medication dataset (ADCM).
   2. Preserve partial medication start/end date precision.
   3. Classify medication timing relative to first study treatment.
   4. Summarize medication use by treatment and medication class.
   5. Perform record, subject, date, and duplicate-key QC.

 INPUT:
   SDTM.CM
   ADAM.ADSL

 OUTPUT:
   ADAM.ADCM
   OUTTAB.CM_SUMMARY
   OUTTAB.CM_CLASS_SUMMARY
   OUTTAB.CM_QC
   OUTTAB.CM_DATE_QC
***********************************************************************/

options validvarname=upcase;
options mprint mlogic symbolgen;

/*---------------------------------------------------------------*
 | 1. LIBRARY ASSIGNMENTS
 *---------------------------------------------------------------*/

libname SDTM "/home/u64646326/clinical_trial_project/data/source";
libname ADAM "/home/u64646326/clinical_trial_project/data/analysis";
libname OUTTAB "/home/u64646326/clinical_trial_project/outputs/tables";


/*---------------------------------------------------------------*
 | 2. PREPARE CONCOMITANT MEDICATION SOURCE
 *---------------------------------------------------------------*/

data work.cm_source;
    set SDTM.CM;

    length CMSTDTC_PF CMENDTC_PF $3;

    format CMSTDT CMENDT
           CMSTDT_LO CMSTDT_HI
           CMENDT_LO CMENDT_HI date9.;

    /*-----------------------------------------------------------*
     | Medication start date precision and interval
     *-----------------------------------------------------------*/

    CMSTDT = .;
    CMSTDT_LO = .;
    CMSTDT_HI = .;
    CMSTDTC_PF = "";

    if not missing(CMSTDTC) then do;

        if lengthn(strip(CMSTDTC)) = 10 then do;
            CMSTDTC_PF = "YMD";
            CMSTDT = input(strip(CMSTDTC), yymmdd10.);
            CMSTDT_LO = CMSTDT;
            CMSTDT_HI = CMSTDT;
        end;

        else if lengthn(strip(CMSTDTC)) = 7 then do;
            CMSTDTC_PF = "YM";
            CMSTDT_LO = input(cats(strip(CMSTDTC), "-01"), yymmdd10.);

            if not missing(CMSTDT_LO) then
                CMSTDT_HI = intnx("month", CMSTDT_LO, 0, "end");
        end;

        else if lengthn(strip(CMSTDTC)) = 4 then do;
            CMSTDTC_PF = "Y";
            CMSTDT_LO = input(cats(strip(CMSTDTC), "-01-01"), yymmdd10.);
            CMSTDT_HI = input(cats(strip(CMSTDTC), "-12-31"), yymmdd10.);
        end;

    end;

    /*-----------------------------------------------------------*
     | Medication end date precision and interval
     *-----------------------------------------------------------*/

    CMENDT = .;
    CMENDT_LO = .;
    CMENDT_HI = .;
    CMENDTC_PF = "";

    if not missing(CMENDTC) then do;

        if lengthn(strip(CMENDTC)) = 10 then do;
            CMENDTC_PF = "YMD";
            CMENDT = input(strip(CMENDTC), yymmdd10.);
            CMENDT_LO = CMENDT;
            CMENDT_HI = CMENDT;
        end;

        else if lengthn(strip(CMENDTC)) = 7 then do;
            CMENDTC_PF = "YM";
            CMENDT_LO = input(cats(strip(CMENDTC), "-01"), yymmdd10.);

            if not missing(CMENDT_LO) then
                CMENDT_HI = intnx("month", CMENDT_LO, 0, "end");
        end;

        else if lengthn(strip(CMENDTC)) = 4 then do;
            CMENDTC_PF = "Y";
            CMENDT_LO = input(cats(strip(CMENDTC), "-01-01"), yymmdd10.);
            CMENDT_HI = input(cats(strip(CMENDTC), "-12-31"), yymmdd10.);
        end;

    end;

    /*-----------------------------------------------------------*
     | Record-level date quality indicators
     *-----------------------------------------------------------*/

    if missing(CMSTDTC) then CMSTMISS = 1;
    else CMSTMISS = 0;

    if missing(CMENDTC) then CMENMISS = 1;
    else CMENMISS = 0;

    if not missing(CMSTDT_LO) and
       not missing(CMENDT_HI) and
       CMENDT_HI < CMSTDT_LO then
        CMNEGFL = 1;
    else
        CMNEGFL = 0;

run;


/*---------------------------------------------------------------*
 | 3. MERGE WITH ADSL
 *---------------------------------------------------------------*/

proc sort data=work.cm_source;
    by USUBJID;
run;

proc sort data=ADAM.ADSL out=work.adsl_sorted;
    by USUBJID;
run;

data ADAM.ADCM;
    merge work.cm_source(in=incm)
          work.adsl_sorted(
              keep=USUBJID TRTSDT TRTEDT TRT01P TRT01A
                   SAFFL ITTFL
          );
    by USUBJID;

    if incm;

    length CMTRTEMFL $1 CMTIMING $20;

    format TRTSDT TRTEDT date9.;

    /*-----------------------------------------------------------*
     | Relative medication timing classification
     |
     | Y = Medication definitely started on/after first dose.
     | N = Medication definitely ended before first dose.
     | Blank = Timing cannot be established from available dates.
     *-----------------------------------------------------------*/

    CMTRTEMFL = "";
    CMTIMING = "UNKNOWN";

    if not missing(TRTSDT) then do;

        if not missing(CMSTDT_LO) and
           CMSTDT_LO >= TRTSDT then do;

            CMTRTEMFL = "Y";
            CMTIMING = "POST-DOSE START";
        end;

        else if not missing(CMENDT_HI) and
                CMENDT_HI < TRTSDT then do;

            CMTRTEMFL = "N";
            CMTIMING = "PRE-DOSE ONLY";
        end;

        else do;

            CMTRTEMFL = "";
            CMTIMING = "TIMING UNCERTAIN";

        end;

    end;

    /* Safety population indicator */

    if SAFFL = "Y" then SAFETYFL = "Y";
    else SAFETYFL = "N";

run;


/*---------------------------------------------------------------*
 | 4. CREATE MEDICATION SUMMARY BY TREATMENT
 *---------------------------------------------------------------*/

proc sql;

    create table work.cm_summary_base as
    select
        TRT01A,
        count(*) as CM_RECORDS,
        count(distinct USUBJID) as SUBJECTS_WITH_CM,
        count(distinct CMDECOD) as DISTINCT_MEDICATIONS,

        sum(case
            when CMTRTEMFL = "Y" then 1
            else 0
        end) as POSTDOSE_RECORDS,

        sum(case
            when CMTRTEMFL = "N" then 1
            else 0
        end) as PREDOSE_RECORDS,

        sum(case
            when missing(CMTRTEMFL) then 1
            else 0
        end) as UNCERTAIN_TIMING_RECORDS,

        sum(CMSTMISS) as MISSING_START_DATES,
        sum(CMENMISS) as MISSING_END_DATES

    from ADAM.ADCM

    where SAFFL = "Y"

    group by TRT01A;

quit;

data OUTTAB.CM_SUMMARY;
    set work.cm_summary_base;
run;


/*---------------------------------------------------------------*
 | 5. MEDICATION CLASS SUMMARY BY TREATMENT
 *---------------------------------------------------------------*/

proc sql;

    create table OUTTAB.CM_CLASS_SUMMARY as
    select
        TRT01A,
        CMCLAS,
        count(*) as CM_RECORDS,
        count(distinct USUBJID) as SUBJECTS_WITH_CM,
        count(distinct CMDECOD) as DISTINCT_MEDICATIONS,

        sum(case
            when CMTRTEMFL = "Y" then 1
            else 0
        end) as POSTDOSE_RECORDS,

        sum(case
            when CMTRTEMFL = "N" then 1
            else 0
        end) as PREDOSE_RECORDS,

        sum(case
            when missing(CMTRTEMFL) then 1
            else 0
        end) as UNCERTAIN_RECORDS

    from ADAM.ADCM

    where SAFFL = "Y"

    group by TRT01A, CMCLAS

    order by TRT01A, CMCLAS;

quit;


/*---------------------------------------------------------------*
 | 6. DATE PRECISION AND MISSINGNESS SUMMARY
 *---------------------------------------------------------------*/

proc sql;

    create table OUTTAB.CM_DATE_QC as

    select
        "START DATE" as DATE_TYPE length=12,
        CMSTDTC_PF as DATE_PRECISION length=3,
        count(*) as RECORDS

    from ADAM.ADCM

    where not missing(CMSTDTC_PF)

    group by CMSTDTC_PF

    union all

    select
        "END DATE" as DATE_TYPE length=12,
        CMENDTC_PF as DATE_PRECISION length=3,
        count(*) as RECORDS

    from ADAM.ADCM

    where not missing(CMENDTC_PF)

    group by CMENDTC_PF;

quit;


/*---------------------------------------------------------------*
 | 7. DUPLICATE EXPOSURE/MEDICATION KEY CHECK
 *---------------------------------------------------------------*/

proc sql;

    create table work.cm_duplicates as
    select
        USUBJID,
        CMSEQ,
        count(*) as DUP_COUNT

    from ADAM.ADCM

    group by USUBJID, CMSEQ

    having count(*) > 1;

quit;


/*---------------------------------------------------------------*
 | 8. SOURCE AND DERIVED RECORD COUNTS
 *---------------------------------------------------------------*/

proc sql noprint;

    select count(*)
    into :SOURCE_CM trimmed
    from SDTM.CM;

    select count(*)
    into :DERIVED_CM trimmed
    from ADAM.ADCM;

    select count(distinct USUBJID)
    into :SOURCE_SUBJ trimmed
    from SDTM.CM;

    select count(distinct USUBJID)
    into :DERIVED_SUBJ trimmed
    from ADAM.ADCM;

    select count(*)
    into :UNMATCHED_CM trimmed
    from ADAM.ADCM
    where missing(SAFFL);

    select sum(CMSTMISS)
    into :MISS_START trimmed
    from ADAM.ADCM;

    select sum(CMENMISS)
    into :MISS_END trimmed
    from ADAM.ADCM;

    select sum(CMNEGFL)
    into :NEG_DUR trimmed
    from ADAM.ADCM;

    select count(*)
    into :DUP_KEYS trimmed
    from work.cm_duplicates;

    select count(*)
    into :SAFETY_CM trimmed
    from ADAM.ADCM
    where SAFFL = "Y";

    select count(*)
    into :NONSAFETY_CM trimmed
    from ADAM.ADCM
    where SAFFL ne "Y";

quit;


/*---------------------------------------------------------------*
 | 9. FINAL QC DATASET
 *---------------------------------------------------------------*/

data OUTTAB.CM_QC;

    length QC_PASS 8;

    SOURCE_CM_RECORDS = input("&SOURCE_CM", best.);
    DERIVED_CM_RECORDS = input("&DERIVED_CM", best.);

    SOURCE_SUBJECTS = input("&SOURCE_SUBJ", best.);
    DERIVED_SUBJECTS = input("&DERIVED_SUBJ", best.);

    UNMATCHED_CM_RECORDS = input("&UNMATCHED_CM", best.);

    MISSING_START_DATES = input("&MISS_START", best.);
    MISSING_END_DATES = input("&MISS_END", best.);

    NEGATIVE_DATE_INTERVALS = input("&NEG_DUR", best.);
    DUPLICATE_CM_KEYS = input("&DUP_KEYS", best.);

    SAFETY_CM_RECORDS = input("&SAFETY_CM", best.);
    NONSAFETY_CM_RECORDS = input("&NONSAFETY_CM", best.);

    if SOURCE_CM_RECORDS = DERIVED_CM_RECORDS and
       SOURCE_SUBJECTS = DERIVED_SUBJECTS and
       UNMATCHED_CM_RECORDS = 0 and
       NEGATIVE_DATE_INTERVALS = 0 and
       DUPLICATE_CM_KEYS = 0
    then QC_PASS = 1;
    else QC_PASS = 0;

run;


/*---------------------------------------------------------------*
 | 10. QC OUTPUTS
 *---------------------------------------------------------------*/

title "Concomitant Medication Derivation QC";

proc print data=OUTTAB.CM_QC noobs;
run;

title "Concomitant Medication Summary by Treatment";

proc print data=OUTTAB.CM_SUMMARY noobs;
run;

title "Concomitant Medication Class Summary";

proc print data=OUTTAB.CM_CLASS_SUMMARY noobs;
run;

title "Concomitant Medication Date Precision QC";

proc print data=OUTTAB.CM_DATE_QC noobs;
run;


/*---------------------------------------------------------------*
 | 11. ADDITIONAL DATASET CONTENTS
 *---------------------------------------------------------------*/

title "ADCM Dataset Structure";

proc contents data=ADAM.ADCM;
run;

title "Concomitant Medication Timing Distribution";

proc freq data=ADAM.ADCM;
    tables CMTIMING*TRT01A / missing;
    where SAFFL = "Y";
run;

title "Concomitant Medication Records by Population";

proc freq data=ADAM.ADCM;
    tables SAFETYFL / missing;
run;

title;
