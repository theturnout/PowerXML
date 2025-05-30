# PowerXML

PowerXML is a set of PowerShell CmdLets that ease use of various XML tooling.

Goals:

- Provide a unified front end for various XML processors
- Automatically gather required dependencies to perform a task

PowerXML currently includes the Polyglot Package Manager (PM), to support dependency management. Post MVP stage, this should become its own project.

# Calling XProc 

```powershell
.\powerxml.ps1 -pipeline testixml_in.xpl -inPort @{'source'='input.txt';'grammar'='grammar.txt'} 
```