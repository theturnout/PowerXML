<?xml version="1.0" encoding="UTF-8"?>
<?xml-model href="http://www.w3.org/ns/xproc" type="application/xml"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:option name="name" required="false"  />
    <p:identity message="Hello, {$name}!">
        <p:with-input>
            <hello>Hello, {$name}!</hello>
        </p:with-input>
    </p:identity>
</p:declare-step>
