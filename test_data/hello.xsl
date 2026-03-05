<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
    
    <xsl:param name="greeting" select="'Hello'"/>
    <xsl:param name="name" select="'World'"/>
    
    <xsl:template match="/">
        <result>
            <message><xsl:value-of select="$greeting"/>, <xsl:value-of select="$name"/>!</message>
        </result>
    </xsl:template>
</xsl:stylesheet>
