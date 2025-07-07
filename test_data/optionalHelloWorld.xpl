<?xml version="1.0" encoding="UTF-8"?>
<?xml-model href="http://www.w3.org/ns/xproc" type="application/xml"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:option name="name" required="false"  />
    <p:input port="source" primary="true" sequence="true" />
    <p:identity message="Hello, {$name}!" />
</p:declare-step>