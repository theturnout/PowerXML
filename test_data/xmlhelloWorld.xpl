<?xml version="1.0" encoding="UTF-8"?>
<?xml-model href="http://www.w3.org/ns/xproc" type="application/xml"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:output port="result" primary="true" />
    <p:identity>
        <p:with-input port="source">
            <p:inline>
                <content>Hello, World!</content>
            </p:inline>
        </p:with-input>
    </p:identity>    
</p:declare-step>