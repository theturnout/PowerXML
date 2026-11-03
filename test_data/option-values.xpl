<p:declare-step xmlns:p="http://www.w3.org/ns/xproc"
	xmlns:xs="http://www.w3.org/2001/XMLSchema"
	xmlns:opt="urn:powerxml:options"
	version="3.0">
	<p:output port="result" serialization="map { 'encoding': 'UTF-8' }"/>
	<p:option name="text" as="xs:string" select="''"/>
	<p:option name="count" as="xs:integer" select="0"/>
	<p:option name="enabled" as="xs:boolean" select="false()"/>
	<p:option name="amount" as="xs:decimal" select="0"/>
	<p:option name="opt:label" as="xs:string" select="''"/>
	<p:option name="value" select="()"/>
	<p:identity>
		<p:with-input>
			<p:inline>
				<result text="{$text}" count="{$count}" enabled="{$enabled}"
					amount="{$amount}" label="{$opt:label}"
					value="{if ($value instance of map(*)) then string($value?label)
						else string-join($value ! string(.), '|')}"
					type="{if ($value instance of xs:string) then 'string'
						else if ($value instance of xs:boolean) then 'boolean'
						else if ($value instance of xs:integer) then 'integer'
						else if ($value instance of xs:decimal) then 'decimal'
						else if ($value instance of xs:float) then 'float'
						else if ($value instance of xs:double) then 'double'
						else if ($value instance of map(*)) then 'map'
						else 'other'}"/>
			</p:inline>
		</p:with-input>
	</p:identity>
</p:declare-step>
