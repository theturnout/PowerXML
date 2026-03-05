<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="2.0" 
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:xs="http://www.w3.org/2001/XMLSchema">
    
    <!-- Import schema for PSVI default attribute values -->
    <xsl:import-schema schema-location="product.xsd"/>
    
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
    
    <xsl:template match="/">
        <!-- Validate input to get PSVI with default attribute values applied -->
        <xsl:variable name="validated-product" as="element(product)">
            <xsl:copy-of select="/product" validation="strict"/>
        </xsl:variable>
        <xsl:apply-templates select="$validated-product"/>
    </xsl:template>
    
    <xsl:template match="product">
        <!-- 
            This template uses PSVI default attribute values:
            - @status defaults to "active"
            - @currency defaults to "USD" 
            - @taxRate defaults to 0.10
            - @warehouse defaults to "MAIN"
        -->
        <invoice>
            <product-info>
                <name><xsl:value-of select="name"/></name>
                <!-- These attributes use PSVI defaults if not specified in source -->
                <status><xsl:value-of select="@status"/></status>
                <currency><xsl:value-of select="@currency"/></currency>
                <warehouse><xsl:value-of select="@warehouse"/></warehouse>
            </product-info>
            <pricing>
                <unit-price><xsl:value-of select="price"/></unit-price>
                <quantity><xsl:value-of select="quantity"/></quantity>
                <subtotal><xsl:value-of select="format-number(price * quantity, '#.00')"/></subtotal>
                <!-- Tax rate from PSVI default attribute -->
                <tax-rate><xsl:value-of select="format-number(@taxRate * 100, '#.##')"/>%</tax-rate>
                <tax-amount><xsl:value-of select="format-number(price * quantity * @taxRate, '#.00')"/></tax-amount>
                <total><xsl:value-of select="format-number(price * quantity * (1 + @taxRate), '#.00')"/></total>
            </pricing>
        </invoice>
    </xsl:template>
</xsl:stylesheet>
