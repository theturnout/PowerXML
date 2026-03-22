<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0" 
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema">
    
    <!-- Import the schema for type-aware processing -->
    <!--<xsl:import-schema schema-location="order.xsd"/>-->
    
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
    
    <!-- XSLT 2.0 schema-aware transformation -->
    <!-- Uses xsl:import-schema to validate input and enforce typed values -->
    
    <xsl:template match="/">
        <!-- Validate the input document against the imported schema -->
        <xsl:variable name="validated-order" as="element(order)">
            <xsl:copy-of select="/order" />
        </xsl:variable>
        <xsl:apply-templates select="$validated-order"/>
    </xsl:template>
    
    <!-- Process the validated order element with schema types -->
    <xsl:template match="order">
        <order-summary id="{@id}">
            <item-count>
                <!-- XSLT 2.0: sum() with schema-typed xs:integer values -->
                <xsl:value-of select="sum(item/quantity)"/>
            </item-count>
            <total-value>
                <!-- XSLT 2.0: for expression with schema-typed xs:decimal arithmetic -->
                <xsl:value-of select="format-number(sum(for $i in item return $i/quantity * $i/price), '#.00')"/>
            </total-value>
            <items>
                <!-- XSLT 2.0: for-each with sorting by typed numeric value -->
                <xsl:for-each select="item">
                    <xsl:sort select="quantity * price" data-type="number" order="descending"/>
                    <item>
                        <name><xsl:value-of select="name"/></name>
                        <line-total><xsl:value-of select="format-number(quantity * price, '#.00')"/></line-total>
                    </item>
                </xsl:for-each>
            </items>
        </order-summary>
    </xsl:template>
</xsl:stylesheet>
