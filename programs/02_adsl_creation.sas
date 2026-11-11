
/*========================================================
  PROJECT: Clinical Trial Statistical Programming
  PROGRAM: 02_create_adsl.sas
  PURPOSE: Create Subject-Level Analysis Dataset (ADSL)
========================================================*/

options validvarname=upcase;

/*--------------------------------------------------------
  1. DEFINE PROJECT PATHS AND LIBRARIES
--------------------------------------------------------*/

%let root=/home/u64646326/clinical_trial_project;

libname sdtm "&root./data/source";
libname adam "&root./data/analysis";


/*--------------------------------------------------------
  2. PREPARE EXPOSURE DATA
  Convert character exposure dates into SAS dates.
--------------------------------------------------------*/

data work.ex_prepared;

    set sdtm.ex;

    length EXSTDT EXENDT 8;

    format EXSTDT EXENDT date9.;

    EXSTDT=input(EXSTDTC,yymmdd10.);
    EXENDT=input(EXENDTC,yymmdd10.);

    label
        EXSTDT="Exposure Start Date"
        EXENDT="Exposure End Date";

run;


/*--------------------------------------------------------
  3. DERIVE SUBJECT-LEVEL TREATMENT DATES
  Earliest exposure start and latest exposure end.
--------------------------------------------------------*/

proc sql;

    create table work.ex_summary as

    select
        USUBJID,

        min(EXSTDT) as TRTSDT format=date9.,

        max(EXENDT) as TRTEDT format=date9.,

        count(*) as EXPN

    from work.ex_prepared

    group by USUBJID;

quit;


/*--------------------------------------------------------
  4. SORT SOURCE DATASETS BEFORE MERGING
--------------------------------------------------------*/

proc sort data=sdtm.dm
          out=work.dm_sorted;

    by USUBJID;

run;


proc sort data=work.ex_summary
          out=work.ex_sorted;

    by USUBJID;

run;


/*--------------------------------------------------------
  5. CREATE SUBJECT-LEVEL ANALYSIS DATASET
--------------------------------------------------------*/

data adam.adsl;

    merge work.dm_sorted(in=IN_DM)
          work.ex_sorted(in=IN_EX);

    by USUBJID;

    /* Retain subjects in the demographic dataset */

    if IN_DM;

    /* Define analysis variable lengths before assignment */

    length
        TRT01P $200
        TRT01A $200
        SAFFL  $1
        ITTFL  $1;

    /* Treatment group variables */

    TRT01P=ARM;
    TRT01A=ACTARM;

    /* Safety population:
       At least one exposure record */

    if IN_EX then SAFFL="Y";
    else SAFFL="N";

    /* Provisional ITT population flag:
       Uses assigned treatment information.
       Requires confirmation against randomization data
       and the study analysis plan. */

    if not missing(ARMCD) and
       upcase(strip(ARMCD)) ne "SCRNFAIL"
    then ITTFL="Y";
    else ITTFL="N";

    /* Analysis date formats */

    format TRTSDT TRTEDT date9.;

    label
        TRT01P = "Planned Treatment"
        TRT01A = "Actual Treatment"
        TRTSDT = "Date of First Exposure"
        TRTEDT = "Date of Last Exposure"
        SAFFL  = "Safety Population Flag"
        ITTFL  = "Provisional ITT Population Flag";

run;


/*--------------------------------------------------------
  6. CHECK ADSL STRUCTURE
--------------------------------------------------------*/

title "ADSL Dataset Structure";

proc contents data=adam.adsl varnum;

run;

title;


/*--------------------------------------------------------
  7. CHECK SUBJECT COUNTS AND POPULATION FLAGS
--------------------------------------------------------*/

title "ADSL Subject and Population Summary";

proc sql;

    select

        count(*) as TOTAL_RECORDS,

        count(distinct USUBJID) as UNIQUE_SUBJECTS,

        sum(SAFFL="Y") as SAFETY_SUBJECTS,

        sum(SAFFL="N") as NON_SAFETY_SUBJECTS,

        sum(ITTFL="Y") as PROVISIONAL_ITT_SUBJECTS,

        sum(ITTFL="N") as NON_ITT_SUBJECTS

    from adam.adsl;

quit;

title;


/*--------------------------------------------------------
  8. CHECK SUBJECT COUNTS BY TREATMENT
--------------------------------------------------------*/

title "Subject Counts by Actual Treatment";

proc freq data=adam.adsl;

    tables TRT01A*SAFFL / missing;

run;

title;


/*--------------------------------------------------------
  9. CHECK TREATMENT DATES
--------------------------------------------------------*/

title "Treatment Date Summary";

proc means data=adam.adsl
           n nmiss min max;

    var TRTSDT TRTEDT;

run;

title;


/*--------------------------------------------------------
  10. CHECK FOR DUPLICATE SUBJECT IDENTIFIERS
--------------------------------------------------------*/

proc sort data=adam.adsl
          out=work.adsl_unique
          nodupkey
          dupout=work.adsl_duplicates;

    by USUBJID;

run;


proc sql;

    title "ADSL Duplicate Subject Check";

    select count(*) as DUPLICATE_RECORDS

    from work.adsl_duplicates;

quit;

title;


/*--------------------------------------------------------
  11. CHECK EXPOSURE DATE CONVERSION
--------------------------------------------------------*/

proc sql;

    title "Exposure Date Conversion Check";

    select

        count(*) as TOTAL_EXPOSURE_RECORDS,

        sum(missing(EXSTDTC)) as MISSING_EXSTDTC,

        sum(missing(EXSTDT)) as UNCONVERTED_EXSTDTC,

        sum(missing(EXENDTC)) as MISSING_EXENDTC,

        sum(missing(EXENDT)) as UNCONVERTED_EXENDTC

    from work.ex_prepared;

quit;

title;


/*--------------------------------------------------------
  12. CHECK SUBJECTS WITHOUT EXPOSURE RECORDS
--------------------------------------------------------*/

proc sql;

    title "Subjects Without Exposure Records";

    select count(*) as SUBJECTS_WITHOUT_EXPOSURE

    from adam.adsl

    where SAFFL="N";

quit;

title;


/*--------------------------------------------------------
  13. FINAL CONFIRMATION
--------------------------------------------------------*/

%put ================================================;
%put ADSL PROGRAM COMPLETED;
%put OUTPUT DATASET: ADAM.ADSL;
%put ================================================;
