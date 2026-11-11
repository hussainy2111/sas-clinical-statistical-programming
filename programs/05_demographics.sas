
/*==============================================================*
 | 05_DEMOGRAPHICS.SAS
 | Purpose: Create safety-population demographics summaries
 | Source:  ADAM.ADSL
 | Output:  DEMOG_AGE and DEMOG_CATEGORICAL
 *==============================================================*/

/*--------------------------------------------------------------*
 | STEP 1: Project paths and library assignments
 *--------------------------------------------------------------*/

%let project=/home/u64646326/clinical_trial_project;

libname adam "&project./data/analysis";

options dlcreatedir;
libname outtab "&project./outputs/tables";
options nodlcreatedir;


/*--------------------------------------------------------------*
 | STEP 2: Remove previous WORK outputs from this program
 *--------------------------------------------------------------*/

proc datasets library=work nolist;
    delete demog_safety
           demog_denominators
           demog_age
           demog_cat_records
           demog_categorical
           demog_cat_qc;
quit;


/*--------------------------------------------------------------*
 | STEP 3: Check source dataset structure
 *--------------------------------------------------------------*/

title "ADSL Dataset Structure";

proc contents data=adam.adsl varnum;
run;


/*--------------------------------------------------------------*
 | STEP 4: Select the safety population
 *--------------------------------------------------------------*/

data work.demog_safety;
    set adam.adsl;

    where SAFFL="Y";

    keep STUDYID
         USUBJID
         AGE
         SEX
         RACE
         ETHNIC
         TRT01A
         SAFFL;
run;

proc sql;
    title "Safety Population by Actual Treatment";

    select TRT01A,
           count(*) as SAFETY_N
    from work.demog_safety
    group by TRT01A
    order by TRT01A;

quit;


/*--------------------------------------------------------------*
 | STEP 5: Calculate treatment-group denominators
 *--------------------------------------------------------------*/

proc sql;
    create table work.demog_denominators as
    select TRT01A,
           count(*) as SAFETY_N
    from work.demog_safety
    group by TRT01A;
quit;

title "Demographics Analysis Denominators";

proc print data=work.demog_denominators noobs label;
    label TRT01A="Actual Treatment"
          SAFETY_N="Safety Population N";
run;


/*--------------------------------------------------------------*
 | STEP 6: Summarize age by treatment group
 *--------------------------------------------------------------*/

proc means data=work.demog_safety
           n mean std median min max
           maxdec=1;

    class TRT01A;
    var AGE;

    output out=work.demog_age
        (drop=_TYPE_ _FREQ_)
        n=AGE_N
        mean=AGE_MEAN
        std=AGE_SD
        median=AGE_MEDIAN
        min=AGE_MIN
        max=AGE_MAX;
run;


/* Add safety population denominators */

proc sort data=work.demog_age;
    by TRT01A;
run;

proc sort data=work.demog_denominators;
    by TRT01A;
run;

data work.demog_age;
    merge work.demog_age(in=a)
          work.demog_denominators(in=b);

    by TRT01A;

    if a and b;

    label TRT01A="Actual Treatment"
          SAFETY_N="Safety Population N"
          AGE_N="Subjects with Age Available"
          AGE_MEAN="Mean"
          AGE_SD="Standard Deviation"
          AGE_MEDIAN="Median"
          AGE_MIN="Minimum"
          AGE_MAX="Maximum";

    format AGE_MEAN AGE_SD AGE_MEDIAN AGE_MIN AGE_MAX 6.1;
run;

title "Demographics: Age by Actual Treatment";

proc print data=work.demog_age noobs label;
run;


/*--------------------------------------------------------------*
 | STEP 7: Create categorical demographic records
 |
 | Missing values are retained as an explicit category.
 | This allows category counts to reconcile to safety N.
 *--------------------------------------------------------------*/

data work.demog_cat_records;

    set work.demog_safety;

    length PARAMETER $20
           CATEGORY $200;

    /* Sex */

    PARAMETER="Sex";

    if missing(SEX) then CATEGORY="Missing";
    else CATEGORY=strip(SEX);

    output;


    /* Race */

    PARAMETER="Race";

    if missing(RACE) then CATEGORY="Missing";
    else CATEGORY=strip(RACE);

    output;


    /* Ethnicity */

    PARAMETER="Ethnicity";

    if missing(ETHNIC) then CATEGORY="Missing";
    else CATEGORY=strip(ETHNIC);

    output;

    keep USUBJID TRT01A PARAMETER CATEGORY;

run;


/*--------------------------------------------------------------*
 | STEP 8: Count subjects by treatment and category
 *--------------------------------------------------------------*/

proc sql;

    create table work.demog_categorical as

    select
        a.TRT01A,
        a.PARAMETER,
        a.CATEGORY,
        count(distinct a.USUBJID) as SUBJECTS,
        b.SAFETY_N,
        calculated SUBJECTS / b.SAFETY_N * 100
            as PERCENT format=6.1

    from work.demog_cat_records as a

    left join work.demog_denominators as b
        on a.TRT01A=b.TRT01A

    group by
        a.TRT01A,
        a.PARAMETER,
        a.CATEGORY,
        b.SAFETY_N

    order by
        a.TRT01A,
        a.PARAMETER,
        a.CATEGORY;

quit;


/*--------------------------------------------------------------*
 | STEP 9: Display categorical demographic summaries
 *--------------------------------------------------------------*/

title "Demographics: Sex, Race, and Ethnicity";

proc print data=work.demog_categorical noobs label;
    var TRT01A
        PARAMETER
        CATEGORY
        SAFETY_N
        SUBJECTS
        PERCENT;

    label TRT01A="Actual Treatment"
          PARAMETER="Demographic Parameter"
          CATEGORY="Category"
          SAFETY_N="Safety Population N"
          SUBJECTS="Number of Subjects"
          PERCENT="Percentage (%)";
run;


/*--------------------------------------------------------------*
 | STEP 10: Independent categorical count reconciliation
 |
 | Each parameter should account for every safety subject,
 | including subjects with missing demographic information.
 *--------------------------------------------------------------*/

proc sql;

    create table work.demog_cat_qc as

    select
        a.TRT01A,
        a.PARAMETER,
        sum(a.SUBJECTS) as CATEGORY_SUBJECT_TOTAL,
        b.SAFETY_N,

        calculated CATEGORY_SUBJECT_TOTAL - b.SAFETY_N
            as DIFFERENCE,

        case
            when calculated CATEGORY_SUBJECT_TOTAL=b.SAFETY_N
                then 1
            else 0
        end as QC_PASS

    from work.demog_categorical as a

    left join work.demog_denominators as b
        on a.TRT01A=b.TRT01A

    group by
        a.TRT01A,
        a.PARAMETER,
        b.SAFETY_N

    order by
        a.TRT01A,
        a.PARAMETER;

quit;

title "QC: Demographic Category Count Reconciliation";

proc print data=work.demog_cat_qc noobs;
run;


/*--------------------------------------------------------------*
 | STEP 11: Check for duplicate subjects
 *--------------------------------------------------------------*/

proc sql;

    create table work.demog_duplicate_check as

    select
        USUBJID,
        count(*) as RECORD_COUNT

    from work.demog_safety

    group by USUBJID

    having count(*) > 1;

quit;

title "QC: Duplicate Subjects in Demographics Population";

proc sql;
    select count(*) as DUPLICATE_SUBJECTS
    from work.demog_duplicate_check;
quit;


/*--------------------------------------------------------------*
 | STEP 12: Save permanent analysis outputs
 *--------------------------------------------------------------*/

data outtab.DEMOG_AGE;
    set work.demog_age;
run;

data outtab.DEMOG_CATEGORICAL;
    set work.demog_categorical;
run;

data outtab.DEMOG_CAT_QC;
    set work.demog_cat_qc;
run;


/*--------------------------------------------------------------*
 | STEP 13: Final output dataset counts
 *--------------------------------------------------------------*/

title "Final Demographics Output Dataset Counts";

proc sql;

    select
        "Age Summary" as DATASET length=30,
        count(*) as RECORDS
    from outtab.DEMOG_AGE

    union all

    select
        "Categorical Summary",
        count(*)
    from outtab.DEMOG_CATEGORICAL

    union all

    select
        "Categorical QC",
        count(*)
    from outtab.DEMOG_CAT_QC;

quit;


/*--------------------------------------------------------------*
 | STEP 14: Program completion
 *--------------------------------------------------------------*/

title "05_DEMOGRAPHICS.SAS Completed";

%put NOTE: Demographics analysis program completed.;
%put NOTE: Review age summaries and categorical QC results.;
%put NOTE: Permanent datasets saved in outputs/tables.;

title;
