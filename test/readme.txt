still work in progress..

a local copy of w3c test files are stored in the files/w3c folder, 
to enable easy updates mostly.

please note: all files contained in the files/w3c folder are licensed under 
both the W3C Test Suite License [1] and the W3C 3-clause BSD License [2].

[1] http://www.w3.org/Consortium/Legal/2008/04-testsuite-license
[2] http://www.w3.org/Consortium/Legal/2008/03-bsd-license

see the SCXML 1.0 Implementation Report Plan page for more details:
http://www.w3.org/Voice/2013/scxml-irp/

custom files in files/ext are likely all derived from existing ones in files/w3c
and take on the appropriate licenses

note, files where obtained with the following command, issued from the files/w3c folder:
wget -m -N -l1 -nH --cut-dirs=2 http://www.w3.org/Voice/2013/scxml-irp/


--- instructions ---


prerequisites

1. install Haxe
(from https://github.com/HaxeFoundation/haxe under "Installing Haxe")

2. install hscript
haxelib install hscript

3. download SaxonHE9-5-1-1J.zip and extract saxon9he.jar (extract manually if required)
wget http://sourceforge.net/projects/saxon/files/Saxon-HE/9.5/SaxonHE9-5-1-1J.zip/download -O SaxonHE9-5-1-1J.zip
unzip SaxonHE9-5-1-1J.zip saxon9he.jar

4. compile build files
haxe build.hxml (windows users: haxe build_win.hxml)

5. copy txml files to flattened source folder
neko copy.n

6. convert txml files for given data model (java needs to be in path)
neko convert.n ecma


running the tests

run the basichttp server:
nekotools server -p 3000 -h localhost -d server/basichttp

running all tests for a given data model
neko run.n ecma

specifying a start test (runs test specified and all tests thereafter)
neko run.n ecma test192.scxml

specifying a start test and number of tests to run
neko run.n ecma test192.scxml 10

