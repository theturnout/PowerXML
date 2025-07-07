<?xml version="1.0" encoding="UTF-8"?>
<?xml-model href="http://www.w3.org/ns/xproc" type="application/xml"?>
<p:declare-step xmlns:p="http://www.w3.org/ns/xproc" name="pipeline" version="3.0">
    <p:output port="result" primary="true" />
    <p:identity>
        <p:with-input>
            <p:inline>
                <supplemental xproc-engine-name="{p:system-property('p:product-name')}"
                    xproc-engine-version="{p:system-property('p:product-version')}"
                    xproc-engine-vendor="{p:system-property('p:vendor')}"
                    psvi-supported="{p:system-property('p:psvi-supported')}" />
            </p:inline>
        </p:with-input>
    </p:identity>
</p:declare-step>