Trapdoor
========

Salesforce login manager for OSX, securely store & manage all your Salesforce.com logins on the Keychain.

Builds with XCode 4.5

See http://www.pocketsoap.com/osx/trapdoor for more details.

Source code is available under the BSD license.

Scripting
---------
Trapdoor includes support for querying the saved credentials. Using standard AppleScript syntax, the `credential/credentials` element can be searched. For instance

```
tell application "Trapdoor"
	set x to every credential where username contains "salesforce.com"
end tell
```
will return a list of credentials that include "salesforce.com" in the username. Valid search and returned fields are `username`, `server`, and `alias`.

To log in to an org specified by a credential, invoke the `login` verb. For example:

```
tell application "Trapdoor"
	set x to every credential where alias contains "Main Dev Org"
	set y to first item of x
	y login
end tell
```

