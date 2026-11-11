
/***********************************************************************
 PROGRAM: 14_ADAE_ADLB_QC.sas
 PURPOSE:
   1. Create permanent QC for ADAE.
   2. Create permanent QC for ADLB.
   3. Check source-to-derived reconciliation.
   4. Check subject linkage and duplicate keys.
   5. Check date precision and baseline consistency.

 OUTPUT:
   OUTTAB.ADAE_QC
   OUTTAB.ADLB_QC
***********************************************************************/

options nonotes nostimer nosource nosyntaxcheck;

libname SDTM "/home/u64646326/clinical_trial_project/data/source";
libname ADAM "/home/u64646326/clinical_trial_project/data/analysis";
libname OUTTAB "/home/u64646326/clinical_trial_project/outputs/tables";


/*===============================================================*
 | PART 1: ADAE QUALITY CONTROL
 *===============================================================*/


/* 1.1 Duplicate AE key check */

proc sql;

    create table work.adae_duplicates as
    select
        USUBJID,
        AESEQ,
        count(*) as DUP_COUNT
    from ADAM.ADAE
    group by USUBJID, AESEQ
    having count(*) > 1;

quit;


/* 1.2 ADAE source and derived metrics */

proc sql noprint;

    select count(*),
           count(distinct USUBJID)
    into :AE_SOURCE_N,
         :AE_SOURCE_SUBJ
    from SDTM.AE;

    select count(*),
           count(distinct USUBJID)
    into :AE_DERIVED_N,
         :AE_DERIVED_SUBJ
    from ADAM.ADAE;

    select count(*)
    into :AE_UNMATCHED
    from ADAM.ADAE
    where missing(TRT01A);

    select count(*)
    into :AE_DUPLICATES
    from work.adae_duplicates;

    select sum(case when AESTDTC_PF = "YMD" then 1 else 0 end),
           sum(case when AESTDTC_PF = "YM" then 1 else 0 end),
           sum(case when AESTDTC_PF = "Y" then 1 else 0 end),
           sum(case when missing(AESTDTC_PF) then 1 else 0 end)
    into :AE_YMD,
         :AE_YM,
         :AE_Y,
         :AE_DATE_UNKNOWN
    from ADAM.ADAE;

    select sum(case when TRTEMFL = "Y" then 1 else 0 end),
           sum(case when TRTEMFL = "N" then 1 else 0 end),
           sum(case when missing(TRTEMFL) then 1 else 0 end)
    into :AE_TE_Y,
         :AE_TE_N,
         :AE_TE_UNK
    from ADAM.ADAE;

quit;


/* 1.3 Permanent ADAE QC dataset */

data OUTTAB.ADAE_QC;

    length QC_PASS 8;

    SOURCE_AE_RECORDS = input("&AE_SOURCE_N", best.);
    DERIVED_AE_RECORDS = input("&AE_DERIVED_N", best.);

    SOURCE_AE_SUBJECTS = input("&AE_SOURCE_SUBJ", best.);
    DERIVED_AE_SUBJECTS = input("&AE_DERIVED_SUBJ", best.);

    UNMATCHED_AE_RECORDS = input("&AE_UNMATCHED", best.);
    DUPLICATE_AE_KEYS = input("&AE_DUPLICATES", best.);

    START_DATE_YMD = input("&AE_YMD", best.);
    START_DATE_YM = input("&AE_YM", best.);
    START_DATE_Y = input("&AE_Y", best.);
    START_DATE_PRECISION_MISSING = input("&AE_DATE_UNKNOWN", best.);

    PROVISIONAL_TEAE_RECORDS = input("&AE_TE_Y", best.);
    NON_TEAE_RECORDS = input("&AE_TE_N", best.);
    UNCLASSIFIED_TEAE_RECORDS = input("&AE_TE_UNK", best.);

    if SOURCE_AE_RECORDS = DERIVED_AE_RECORDS and
       SOURCE_AE_SUBJECTS = DERIVED_AE_SUBJECTS and
       UNMATCHED_AE_RECORDS = 0 and
       DUPLICATE_AE_KEYS = 0 and
       sum(START_DATE_YMD,
           START_DATE_YM,
           START_DATE_Y,
           START_DATE_PRECISION_MISSING) = DERIVED_AE_RECORDS
    then QC_PASS = 1;
    else QC_PASS = 0;

run;


/*===============================================================*
 | PART 2: ADLB QUALITY CONTROL
 *===============================================================*/


/* 2.1 Duplicate laboratory key check */

proc sql;

    create table work.adlb_duplicates as
    select
        USUBJID,
        LBSEQ,
        count(*) as DUP_COUNT
    from ADAM.ADLB
    group by USUBJID, LBSEQ
    having count(*) > 1;

quit;


/* 2.2 Source versus derived baseline flag comparison */

proc sql;

    create table work.adlb_baseline_check as
    select
        count(*) as TOTAL_RECORDS,

        sum(case
            when coalescec(strip(LBBLFL), "") =
                 coalescec(strip(ABLFL), "")
            then 0
            else 1
        end) as BASELINE_FLAG_DISCORDANCE

    from ADAM.ADLB;

quit;


/* 2.3 ADLB source and derived metrics */

proc sql noprint;

    select count(*),
           count(distinct USUBJID)
    into :LB_SOURCE_N,
         :LB_SOURCE_SUBJ
    from SDTM.LB;

    select count(*),
           count(distinct USUBJID)
    into :LB_DERIVED_N,
         :LB_DERIVED_SUBJ
    from ADAM.ADLB;

    select count(*)
    into :LB_UNMATCHED
    from ADAM.ADLB
    where missing(TRT01A);

    select count(*)
    into :LB_DUPLICATES
    from work.adlb_duplicates;

    select BASELINE_FLAG_DISCORDANCE
    into :LB_BASE_DISCORD
    from work.adlb_baseline_check;

    select sum(case
                 when not missing(CHG) and
                      not missing(AVAL) and
                      not missing(BASE) and
                      abs(CHG - (AVAL - BASE)) > 0.000001
                 then 1
                 else 0
               end),

           sum(case
                 when not missing(PCHG) and
                      not missing(CHG) and
                      not missing(BASE) and
                      abs(PCHG - (CHG / BASE * 100)) > 0.000001
                 then 1
                 else 0
               end)

    into :LB_CHG_ERRORS,
         :LB_PCHG_ERRORS

    from ADAM.ADLB;

quit;


/* 2.4 Permanent ADLB QC dataset */

data OUTTAB.ADLB_QC;

    length QC_PASS 8;

    SOURCE_LB_RECORDS = input("&LB_SOURCE_N", best.);
    DERIVED_LB_RECORDS = input("&LB_DERIVED_N", best.);

    SOURCE_LB_SUBJECTS = input("&LB_SOURCE_SUBJ", best.);
    DERIVED_LB_SUBJECTS = input("&LB_DERIVED_SUBJ", best.);

    UNMATCHED_LB_RECORDS = input("&LB_UNMATCHED", best.);
    DUPLICATE_LB_KEYS = input("&LB_DUPLICATES", best.);

    BASELINE_FLAG_DISCORDANCE = input("&LB_BASE_DISCORD", best.);

    CHG_CALCULATION_ERRORS = input("&LB_CHG_ERRORS", best.);
    PCHG_CALCULATION_ERRORS = input("&LB_PCHG_ERRORS", best.);

    if SOURCE_LB_RECORDS = DERIVED_LB_RECORDS and
       SOURCE_LB_SUBJECTS = DERIVED_LB_SUBJECTS and
       UNMATCHED_LB_RECORDS = 0 and
       DUPLICATE_LB_KEYS = 0 and
       BASELINE_FLAG_DISCORDANCE = 0 and
       CHG_CALCULATION_ERRORS = 0 and
       PCHG_CALCULATION_ERRORS = 0
    then QC_PASS = 1;
    else QC_PASS = 0;

run;


/*===============================================================*
 | PART 3: DISPLAY QC RESULTS
 *===============================================================*/

title "ADAE Quality Control";

proc print data=OUTTAB.ADAE_QC noobs;
run;

title "ADLB Quality Control";

proc print data=OUTTAB.ADLB_QC noobs;
run;

title "ADAE Dataset Contents";

proc contents data=ADAM.ADAE;
run;

title "ADLB Dataset Contents";

proc contents data=ADAM.ADLB;
run;

title;
