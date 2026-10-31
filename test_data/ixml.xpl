<p:declare-step xmlns:err="http://www.w3.org/ns/xproc-error" xmlns:p="http://www.w3.org/ns/xproc" version="3.0">
   <p:output port="result"/>
   <p:invisible-xml>
      <p:with-input port="grammar">
         <p:inline content-type="text/plain">
                  date: s?, day, s, month, (s, year)? .
                  -s: -" "+ .
                  day: digit, digit? .
                  -digit: "0"; "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9".
                  month: "January"; "February"; "March"; "April";
                  "May"; "June"; "July"; "August";
                  "September"; "October"; "November"; "December".
                  year: (digit, digit)?, digit, digit .
               </p:inline>
      </p:with-input>
      <p:with-input port="source">
         <p:inline content-type="text/plain">5 March 2026</p:inline>
      </p:with-input>
   </p:invisible-xml>
</p:declare-step>