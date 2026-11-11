
/*==============================================================*
 | 04_CREATE_ADLB.SAS
 |
 | Purpose:
 |   Create a laboratory analysis dataset.
 |
 | Input:
 |   SDTM.LB
 |   ADAM.ADSL
 |
 | Output:
 |   ADAM.ADLB
 |
 | Baseline:
 |   Latest nonmissing laboratory result on or before first
 |   exposure, separately for each subject and laboratory test.
 |
 | ABLFL is derived from this selection.
 | LBBLFL is retained from the source for comparison.
 *==============================================================*/

options validvarname=upcase;
options nodate nonumber;

%let root=/home/u64646326/clinical_trial_project;

libname sdtm "&root./data/source";
libname adam "&root./data/analysis";


/*--------------------------------------------------------------*
 | 1. Prepare subject-level treatment information
 *--------------------------------------------------------------*/

data work.adsl_lb;
    set adam.adsl;

    keep USUBJID
         TRT01P
         TRT01A
         TRTSDT
         TRTEDT
         SAFFL
         ITTFL;
run;


/*--------------------------------------------------------------*
 | 2. Prepare laboratory source records
 *--------------------------------------------------------------*/

data work.lb_prepared;

    set sdtm.lb;

    length LBDT 8;

    format LBDT date9.;

    /* LBDTC contains ISO datetime, e.g. 2013-12-26T14:45 */
    if not missing(LBDTC) then
        LBDT=input(substr(LBDTC,1,10),yymmdd10.);

    /* Analysis value in standardized units */
    AVAL=LBSTRESN;

    /* Standardized reference ranges */
    ANRLO=LBSTNRLO;
    ANRHI=LBSTNRHI;

    /* Retain the source abnormality indicator */
    length ANRIND $200;
    ANRIND=strip(LBNRIND);

    label LBDT="Laboratory Collection Date"
          AVAL="Analysis Value"
          ANRLO="Analysis Reference Range Lower Limit"
          ANRHI="Analysis Reference Range Upper Limit"
          ANRIND="Analysis Reference Range Indicator";

run;


/*--------------------------------------------------------------*
 | 3. Merge laboratory records with ADSL
 *--------------------------------------------------------------*/

proc sort data=work.lb_prepared
          out=work.lb_sorted;

    by USUBJID LBTESTCD LBDT LBSEQ;

run;

proc sort data=work.adsl_lb
          out=work.adsl_lb_sorted;

    by USUBJID;

run;


/*--------------------------------------------------------------*
 | 4. Identify eligible baseline observations
 |
 | Criteria:
 |   - A valid laboratory collection date
 |   - A nonmissing standardized numeric result
 |   - Collection date on or before first exposure
 |   - A known first exposure date
 *--------------------------------------------------------------*/

data work.lb_baseline_candidates;

    merge work.lb_sorted(in=IN_LB)
          work.adsl_lb_sorted(in=IN_ADSL);

    by USUBJID;

    if IN_LB and IN_ADSL;

    if not missing(LBDT)
       and not missing(AVAL)
       and not missing(TRTSDT)
       and LBDT <= TRTSDT;

run;


/*--------------------------------------------------------------*
 | 5. Select the latest eligible baseline record
 |
 | Sort latest collection date first.
 | LBSEQ breaks ties when multiple records have the same date.
 *--------------------------------------------------------------*/

proc sort data=work.lb_baseline_candidates
          out=work.lb_baseline_sorted;

    by USUBJID
       LBTESTCD
       descending LBDT
       descending LBSEQ;

run;


/* Keep one baseline record per subject and laboratory test */

proc sort data=work.lb_baseline_sorted
          out=work.lb_baseline_pick
          nodupkey;

    by USUBJID LBTESTCD;

run;


/*--------------------------------------------------------------*
 | 6. Prepare baseline values for merging
 *--------------------------------------------------------------*/

data work.lb_baseline;

    set work.lb_baseline_pick;

    keep USUBJID LBTESTCD AVAL LBDT LBSEQ;

    rename AVAL=BASE
           LBDT=BASEDT
           LBSEQ=BASESEQ;

run;


/*--------------------------------------------------------------*
 | 7. Sort baseline records
 *--------------------------------------------------------------*/

proc sort data=work.lb_baseline;
    by USUBJID LBTESTCD;
run;


/*--------------------------------------------------------------*
 | 8. Attach baseline values to all laboratory observations
 *--------------------------------------------------------------*/

data adam.adlb;

    merge work.lb_sorted(in=IN_LB)
          work.adsl_lb_sorted(in=IN_ADSL)
          work.lb_baseline(in=IN_BASE);

    by USUBJID;

    /* Keep all original LB records */
    if IN_LB;

    length ABLFL $1;

    /* Flag the selected analysis baseline observation */
    ABLFL="";

    if IN_BASE and LBSEQ=BASESEQ then
        ABLFL="Y";

    /* Change from baseline */
    if not missing(AVAL) and not missing(BASE) then
        CHG=AVAL-BASE;
    else
        CHG=.;

    /* Percentage change from baseline */
    if not missing(AVAL)
       and not missing(BASE)
       and BASE ne 0 then
        PCHG=((AVAL-BASE)/BASE)*100;
    else
        PCHG=.;

    format TRTSDT TRTEDT LBDT BASEDT date9.;

    label ABLFL="Analysis Baseline Flag"
          BASE="Baseline Analysis Value"
          BASEDT="Baseline Collection Date"
          BASESEQ="Baseline Laboratory Sequence"
          CHG="Change from Baseline"
          PCHG="Percentage Change from Baseline";

run;


/*--------------------------------------------------------------*
 | 9. Inspect ADLB structure
 *--------------------------------------------------------------*/

title "ADLB Dataset Structure";

proc contents data=adam.adlb varnum;
run;


/*--------------------------------------------------------------*
 | 10. Record counts and baseline summaries
 *--------------------------------------------------------------*/

title "ADLB Record Counts and Baseline Summary";

proc sql;

    select count(*) as TOTAL_LB_RECORDS,
           count(distinct USUBJID) as SUBJECTS_WITH_LB,
           sum(ABLFL="Y") as DERIVED_BASELINE_RECORDS,
           sum(missing(AVAL)) as MISSING_ANALYSIS_VALUES,
           sum(missing(BASE)) as MISSING_BASELINE_VALUES,
           sum(missing(CHG)) as MISSING_CHANGE_VALUES
    from adam.adlb;

quit;


/*--------------------------------------------------------------*
 | 11. Compare source and derived baseline flags
 *--------------------------------------------------------------*/

title "Source Versus Derived Baseline Flags";

proc freq data=adam.adlb;

    tables LBBLFL*ABLFL / missing;

run;


/*--------------------------------------------------------------*
 | 12. Review selected laboratory tests
 *--------------------------------------------------------------*/

title "Laboratory Results by Test";

proc means data=adam.adlb
           n nmiss mean std min median max;

    class LBTESTCD;

    var AVAL BASE CHG PCHG;

run;


/*--------------------------------------------------------------*
 | 13. Review abnormal laboratory indicators
 *--------------------------------------------------------------*/

title "Laboratory Abnormality Indicators";

proc freq data=adam.adlb;

    tables LBTESTCD*ANRIND / missing;

run;


/*--------------------------------------------------------------*
 | 14. Check duplicate laboratory keys
 *--------------------------------------------------------------*/

proc sort data=adam.adlb
          out=work.adlb_unique
          nodupkey
          dupout=work.adlb_duplicates;

    by USUBJID LBSEQ;

run;

title "ADLB Duplicate Key Check";

proc sql;

    select count(*) as DUPLICATE_LB_KEYS
    from work.adlb_duplicates;

quit;


/*--------------------------------------------------------------*
 | 15. Check laboratory date conversions
 *--------------------------------------------------------------*/

title "ADLB Date Conversion Checks";

proc sql;

    select count(*) as TOTAL_RECORDS,
           sum(missing(LBDTC)) as MISSING_SOURCE_DATES,
           sum(not missing(LBDTC) and missing(LBDT))
               as UNCONVERTED_DATES
    from adam.adlb;

quit;


/*--------------------------------------------------------------*
 | 16. Check unmatched laboratory subjects
 *--------------------------------------------------------------*/

title "LB Subjects Without ADSL Treatment Information";

proc sql;

    select count(distinct L.USUBJID) as UNMATCHED_LB_SUBJECTS

    from work.lb_sorted as L

    left join work.adsl_lb_sorted as A

        on L.USUBJID=A.USUBJID

    where missing(A.USUBJID);

quit;

title;
