# Changelog

## Concept
- 0.9
    - 2019-03-17 Copied code
- 0.9.1
    - 2019-04-06 Removed attributes not used
- 0.9.2
    - 2019-04-13 Create username and set functions
- 0.9.3
    - 2019-04-20 Included Simulation argument
- 0.9.4
    - 2019-04-28 working concept and user to contact idea worked out
- 0.9.5
    - 2019-06-16 Move Home & profile and edit in user object when lid af
- 0.9.6
    - 2019-07-09 Error with duplicate username loop. Fixed by initializing sam_ori. Fixed extra log in output folder
    - 
<hr>

## Version 1

- 1.0.0
    - 2020-07-02 Change primary key and optimized functions. Created backup
- 1.0.1
    - 2020-07-03 Added additional info when change of fields is performed, added https://lazywinadmin.com/2015/05/powershell-remove-diacritics-accents.html method2
- 1.0.2
    - 2020-07-03 Fix for encoding. omit -Encoding --> UTF8, -Encoding Default --> do nothing https://stackoverflow.com/questions/48947151/import-csv-export-csv-with-german-umlauts-%C3%A4-%C3%B6-%C3%BC
- 1.0.3
    - 2020-07-17 Added mailnickname for azure
- 1.0.4
    - 2020-07-28 Fix for phone numbers
- 1.0.5
    - 2020-07-29 Update fix for more numbers and debug
- 1.0.5a
    - 2020-08-06 Created generalized version for GitHub (not this one!)
- 1.0.6
    - 2020-09-08 Validation of email fixed
- 1.0.7
    - 2020-09-23 last check of contact creation for old members
- 1.0.8
    - 2021-06-12 keep input logs for longer time
- 1.0.9
    - 2021-08-01 Fix officephone for change-users set

- 1.0.10
    - 2021-10-31 Disable profilepath
- 1.0.10
    - 2022-01-18 Fix homedrive bug due to commented profilepath +  import with utf8
- 1.0.11
    - 2022-02-10 Exclude users without valid name2
- 1.0.12
    - 2022-02-10 Rename lid-af users to $samaccountname
- 1.0.13
    - 2022-07-29 fix new header, line 203

- 1.1.0
    - 2021-10-01 Rewrite / cleanup code, so Github and local are identical
- 1.1.1
    - 2021-10-04 Add secondary email

- 1.2.0
    - 2022-12-02 Rewrite / cleanup
- 1.2.1
    - 2022-12-04 Fix PSScriptanalyser stuff
- 1.3.0
    - 2023-12-02 Fix issues with paths and DNS Suffix
<hr>

## Version 2

- 2.0.0.
    - 2024-05-31 Convert to MgGraph
