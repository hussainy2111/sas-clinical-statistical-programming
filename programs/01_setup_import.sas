/*========================================================
  PROJECT: Clinical Trial Statistical Programming
  PROGRAM: 01_setup_import.sas
  PURPOSE: Import CDISC SDTM XPT datasets
========================================================*/

options validvarname=upcase;
options mprint mlogic symbolgen;

/* 1. SET PROJECT PATH */

%let root=/home/YOUR_SAS_USER_ID/clinical_trial_project;

/* 2. DEFINE FOLDER PATHS */

%let raw=&root./data/source;
%let analysis=&root./data/analysis;
%let output=&root./outputs;

/* 3. ASSIGN SAS LIBRARIES */

libname sdtm "&raw.";
libname adam "&analysis.";

/* 4. CHECK SOURCE FILES */

%macro check_file(file=);

    %let fileref=checkfile;

    filename &fileref "&raw./&file.";

    %if %sysfunc(fexist(&fileref)) %then
        %put NOTE: FILE FOUND: &file.;
    %else
        %put ERROR: FILE NOT FOUND: &file.;

    filename &fileref clear;

%mend;

%check_file(file=dm.xpt);
%check_file(file=ex.xpt);
%check_file(file=ae.xpt);
%check_file(file=lb.xpt);


/* 5. MACRO TO IMPORT XPT FILES */

%macro import_xpt(file=);

    %put NOTE: ======================================;
    %put NOTE: IMPORTING &file.;
    %put NOTE: ======================================;

    libname xptin xport "&raw./&file.";

    proc contents data=xptin._all_ nods;
    run;

    proc copy in=xptin out=sdtm;
    run;

    libname xptin clear;

%mend;


/* 6. IMPORT THE FOUR REQUIRED DOMAINS */

%import_xpt(file=dm.xpt);
%import_xpt(file=ex.xpt);
%import_xpt(file=ae.xpt);
%import_xpt(file=lb.xpt);


/* 7. CHECK IMPORTED DATASETS */

title "Imported SDTM Datasets";

proc datasets library=sdtm;
run;
quit;

title;


/* 8. REVIEW VARIABLES IN EACH DOMAIN */

proc contents data=sdtm.dm;
run;

proc contents data=sdtm.ex;
run;

proc contents data=sdtm.ae;
run;

proc contents data=sdtm.lb;
run;


/* 9. DISPLAY RECORD COUNTS */

proc sql;

    title "SDTM Dataset Record Counts";

    select "DM" as DOMAIN length=8,
           count(*) as RECORDS
    from sdtm.dm

    union all

    select "EX",
           count(*)
    from sdtm.ex

    union all

    select "AE",
           count(*)
    from sdtm.ae

    union all

    select "LB",
           count(*)
    from sdtm.lb;

quit;

title;