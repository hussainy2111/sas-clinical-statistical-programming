
/***************************************************************
  PROGRAM: 09_LAB_ABNORMALITY.sas
  PURPOSE: Summarize post-baseline laboratory abnormalities
           by treatment and laboratory parameter.

  INPUT:
    ADAM.ADLB

  OUTPUT:
    OUTTAB.LAB_ABNORMALITY
    OUTTAB.LAB_ABNORMALITY_QC
    OUTTAB.LAB_ABNORMALITY_RECON
***************************************************************/

options validvarname=upcase;

/*-------------------------------------------------------------*
 | STEP 1: Prepare post-baseline laboratory records
 *-------------------------------------------------------------*/

data work.lab_postbaseline;
    set adam.adlb;

    where saffl = "Y"
      and not missing(aval)
      and not missing(trt01a)
      and not missing(paramcd)
      and not missing(usubjid)
      and not missing(ady)
      and ady > 0;

    length LAB_STATUS $20;

    LAB_STATUS = upcase(strip(anrind));

    if LAB_STATUS in ("LOW", "NORMAL", "HIGH");

    keep usubjid trt01a paramcd param ady aval anrind lab_status;
run;


/*-------------------------------------------------------------*
 | STEP 2: Count post-baseline records by status
 *-------------------------------------------------------------*/

proc sql;
    create table work.lab_status_records as
    select
        trt01a,
        paramcd,
        param,
        lab_status,
        count(*) as N_RECORDS
    from work.lab_postbaseline
    group by trt01a, paramcd, param, lab_status;
quit;


/*-------------------------------------------------------------*
 | STEP 3: Count distinct subjects by status
 *-------------------------------------------------------------*/

proc sort data=work.lab_postbaseline
          out=work.lab_subject_status nodupkey;
    by trt01a paramcd param lab_status usubjid;
run;

proc sql;
    create table work.lab_status_subjects as
    select
        trt01a,
        paramcd,
        param,
        lab_status,
        count(*) as N_SUBJECTS
    from work.lab_subject_status
    group by trt01a, paramcd, param, lab_status;
quit;


/*-------------------------------------------------------------*
 | STEP 4: Calculate total post-baseline records and subjects
 |         for each treatment and laboratory parameter
 *-------------------------------------------------------------*/

proc sql;
    create table work.lab_parameter_totals as
    select
        trt01a,
        paramcd,
        param,
        count(*) as TOTAL_RECORDS
    from work.lab_postbaseline
    group by trt01a, paramcd, param;

    create table work.lab_parameter_subject_totals as
    select
        trt01a,
        paramcd,
        param,
        count(distinct usubjid) as TOTAL_SUBJECTS
    from work.lab_postbaseline
    group by trt01a, paramcd, param;
quit;


/*-------------------------------------------------------------*
 | STEP 5: Combine counts and calculate percentages
 *-------------------------------------------------------------*/

proc sql;
    create table work.lab_abnormality as
    select
        a.trt01a,
        a.paramcd,
        a.param,
        a.lab_status,
        a.n_records,
        b.n_subjects,
        c.total_records,
        d.total_subjects,

        (a.n_records / c.total_records) * 100
            as PCT_RECORDS format=6.1,

        (b.n_subjects / d.total_subjects) * 100
            as PCT_SUBJECTS format=6.1

    from work.lab_status_records as a

    left join work.lab_status_subjects as b
        on a.trt01a = b.trt01a
       and a.paramcd = b.paramcd
       and a.lab_status = b.lab_status

    left join work.lab_parameter_totals as c
        on a.trt01a = c.trt01a
       and a.paramcd = c.paramcd

    left join work.lab_parameter_subject_totals as d
        on a.trt01a = d.trt01a
       and a.paramcd = d.paramcd

    order by a.paramcd, a.trt01a, a.lab_status;
quit;


/*-------------------------------------------------------------*
 | STEP 6: QC - Check record and subject counts
 *-------------------------------------------------------------*/

proc sql;
    create table work.lab_abnormality_qc as
    select
        a.trt01a,
        a.paramcd,
        a.param,
        a.lab_status,

        a.n_records as SUMMARY_RECORDS,
        b.expected_records as SOURCE_RECORDS,

        a.n_subjects as SUMMARY_SUBJECTS,
        b.expected_subjects as SOURCE_SUBJECTS,

        case
            when a.n_records = b.expected_records
             and a.n_subjects = b.expected_subjects
            then 1
            else 0
        end as QC_PASS

    from work.lab_abnormality as a

    left join
    (
        select
            trt01a,
            paramcd,
            param,
            lab_status,
            count(*) as expected_records,
            count(distinct usubjid) as expected_subjects
        from work.lab_postbaseline
        group by trt01a, paramcd, param, lab_status
    ) as b

    on a.trt01a = b.trt01a
   and a.paramcd = b.paramcd
   and a.lab_status = b.lab_status

    order by a.paramcd, a.trt01a, a.lab_status;
quit;


/*-------------------------------------------------------------*
 | STEP 7: Reconcile included records against source records
 *-------------------------------------------------------------*/

proc sql noprint;
    select count(*)
    into :input_records trimmed
    from work.lab_postbaseline;

    select sum(n_records)
    into :summarized_records trimmed
    from work.lab_status_records;
quit;

data work.lab_abnormality_recon;
    INPUT_RECORDS = &input_records;
    SUMMARIZED_RECORDS = &summarized_records;

    DIFFERENCE = INPUT_RECORDS - SUMMARIZED_RECORDS;

    if DIFFERENCE = 0 then QC_PASS = 1;
    else QC_PASS = 0;
run;


/*-------------------------------------------------------------*
 | STEP 8: Display results
 *-------------------------------------------------------------*/

title "Post-baseline Laboratory Abnormality Summary";

proc print data=work.lab_abnormality noobs;
run;

title "Laboratory Abnormality Quality Control";

proc print data=work.lab_abnormality_qc noobs;
run;

title "Laboratory Abnormality Record Reconciliation";

proc print data=work.lab_abnormality_recon noobs;
run;


/*-------------------------------------------------------------*
 | STEP 9: Save permanent output datasets
 *-------------------------------------------------------------*/

data outtab.lab_abnormality;
    set work.lab_abnormality;
run;

data outtab.lab_abnormality_qc;
    set work.lab_abnormality_qc;
run;

data outtab.lab_abnormality_recon;
    set work.lab_abnormality_recon;
run;


/*-------------------------------------------------------------*
 | STEP 10: Final output inventory
 *-------------------------------------------------------------*/

title "Laboratory Abnormality Output Dataset Counts";

proc sql;
    select "LAB_ABNORMALITY" as DATASET,
           count(*) as ROWS
    from outtab.lab_abnormality

    union all

    select "LAB_ABNORMALITY_QC",
           count(*)
    from outtab.lab_abnormality_qc

    union all

    select "LAB_ABNORMALITY_RECON",
           count(*)
    from outtab.lab_abnormality_recon;
quit;

title;
