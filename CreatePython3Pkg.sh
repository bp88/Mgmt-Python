#!/bin/zsh

# This script is inspired by the MacAdmins Python project: https://github.com/macadmins/python
# which itself was inspired by https://github.com/gregneagle/relocatable-python
#
# What this script will do is generate a package with the following structure:
# |____opt
# | |____mgmt
# | | |____bin
# | | | |____python3 -> /opt/mgmt/frameworks/Python.framework/Versions/Current/bin/python3
# | | |____frameworks
# | | | |____python3.framework
#
# You can either generate a minimal or recommended Python 3 package. The differences are
#   in the modules that are included. Run the script without any parameters to get a list.
# It is expected that your python scripts should use the following shebang:
#       #!/opt/mgmt/bin/python3
#
# The rationale for the choices made here are as follows:
#   "mgmt" is generic and does not reference the name of any specific company/org.
#   "mgmt" is a short acronym that insinuates that it's for management of the computer.
#   It's not commonly used by popular packaging tools like homebrew and won't conflict
#       with MacPorts.
#   It's not part of $PATH which decreases the chances there's a conflict if a user
#       installs their own version of Python 3.
#   It allows us to create a somewhat short symbolic link: /opt/mgmt/bin/python3
#   /opt is protected in macOS 10.15 because the root volume is read-only. Apple is
#       acknowledging this directory is a conventional path used by tools by creating
#       it in 10.15 and not using it themselves/leaving it blank.
#   /opt is hidden in macOS 10.15 by default.
#
# The following considerations were also made:
#
# /usr/local is one location that is often used for personally installed command line
#   tools. However certain tools like homebrew make use of this path and do insist on
#   changing ownership of it. If you support developers in your organization, then it's
#   quite likely they will make use of this path to install many other tools and/or homebrew.
#   It's best just to avoid any potential conflicts. This path is by default not visible to users.
# /Library/CompanyName is another recommendation. The idea here is that you'd have a
#   folder where you keep commonly used company resources, tools, etc. that are relied on
#   for device management. This path is visible to users, but you can certainly hide it if
#   you preferred. The one downside here would be that the path would be a little longer
#   to reference than usual. However you can take care of that by creating a symbolic link
#   in a more traditional path so that it's easier to reference.
# /opt is another path that's been recommended. It exists by default in macOS 10.15, but
#   not in previous versions of macOS. It is hidden by default. MacPorts makes use of
#   /opt/local. However they do not make any such recommendations about changing
#   ownership. The concerns about a potential conflict still exist if you use /opt/local
#   and a developer has installed MacPorts though.
# Some admins have suggested using your company acronym regardless of the directory such
#   as (e.g. /usr/acme or/opt/acme). In 10.15, you cannot write to /usr since it's
#   protected by System Integrity Protection.
# Do you want this version of Python to be available to end-users? If you want this
#   version of Python to be available to end-users then you'll want to aware of what is 
#   available in $PATH. For example, if you created a symbolic link to your Python in
#   /usr/local/bin/python3, then you end up with a situation where the your Python could
#   impact the end user relying on it. Likewise, if you make your python3 available in
#   $PATH and the end user ends up installing Python 3 which is also available in $PATH,
#   you may end up with a conflict with your scripts.

# Get the logged in user's user name - thanks to Erik Burglund -
# http://erikberglund.github.io/2018/Get-the-currently-logged-in-user,-in-Bash/
loggedInUser=$(/usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }} ')

#Variables
tmpDir="/private/tmp/RP"
repoName="relocatable-python"
pythonVersion="3.8.3"
reloPythonURL="https://github.com/gregneagle/$repoName/archive/master.zip"
reloPythonZip="$tmpDir/reloPython.zip"
reloPythonPkgRoot="$tmpDir/pkgRoot"
reloPythonPkgScript="$tmpDir/scripts"
mgmtPath="/opt/mgmt"

reqMinimal="pyobjc
xattr"
reqRecommended="arrow
aspy.yaml
atomicwrites
black
boto
entrypoints
flake8
flake8-bugbear
funcsigs
importlib-metadata
isort
packaging
pre-commit
pyobjc
pytest
pytest-docker
python-dotenv
requests
rsa
slacker
Sphinx
tokenize-rt
virtualenv
xattr"

help() {
    # Display script usage
    echo "Based off the work found at: https://github.com/gregneagle/relocatable-python"
    echo "This script will create a Relocatable Python installer package with a set list\nof modules and output it to your Desktop folder."
    echo "The python modules are not tied to a specific version. The original project\nincluded xattr 0.6.4 since it's the version that works in the Recovery environment."
    echo "The package that is generated by this script is meant for being run in a\nregular macOS installation."
    echo "    Available options:"
    echo "      minimal"
    echo "        A python framework with the original libraries as intended by the original relocatable python:\n$(echo $reqMinimal | sed 's/^/          /')"
    echo ""
    echo "      recommended"
    echo "        A python framework with libraries for as many macadmin tools as possible:\n$(echo $reqRecommended | sed 's/^/          /')"
    echo ""
    echo "Note: If you want to install a version of Python 3 with only the official\nstandard libraries, download and install the Xcode Command Line Tools from Apple\nwhich include Python 3. These will get updated whenever Apple releases new\nXcode Command Line Tool updates."
    exit 1
}

createPostInstall() {
    # Create postinstall script for package
    echo '#!/bin/zsh' > "$reloPythonPkgScript/postinstall"
    echo "[ -d /opt ] && /usr/bin/chflags hidden /opt" >> "$reloPythonPkgScript/postinstall"
    echo "/usr/bin/chflags hidden $mgmtPath" >> "$reloPythonPkgScript/postinstall"
    /bin/chmod a+x "$reloPythonPkgScript/postinstall"
}

if [ -n "$1" ]; then
    if [[ "$1" == "minimal" ]]; then
        reqChoice=$1
    elif [[ "$1" == "recommended" ]]; then
        reqChoice=$1
    else
        echo "Unrecognized positional argument specified."
        help
    fi
else
    help
fi

# Root Check
[[ $(/usr/bin/id -u) -ne 0 ]] && echo "This tool requires elevated access to run." && exit 1

# Clear temporary working space
[[ -d "$tmpDir" ]] && echo "Clearing working space" && /bin/rm -rf "$tmpDir"

# Create temporary working space
/bin/mkdir -p "$tmpDir"
echo "Creating temporary working space."

# Create pkg root structure
/bin/mkdir -p "$reloPythonPkgRoot/bin"
/bin/mkdir -p "$reloPythonPkgRoot/frameworks"
/bin/mkdir -p "$reloPythonPkgScript"
echo "Creating package root structure."

# Create symbolic link
/bin/ln -s "$mgmtPath/frameworks/python3.framework/Versions/Current/bin/python3" "$reloPythonPkgRoot"/bin/python3

# Download Relocatable Python
echo "Downloading Relocatable Python script from $reloPythonURL"
/usr/bin/curl "$reloPythonURL" -L -o "$reloPythonZip"

# Exit if download failed
[[ $? -ne 0 ]] && echo "Relocatable Python zip could not be downloaded. Error Code: $?" && exit 1

# Unzip downloaded zip archive
/usr/bin/unzip "$reloPythonZip" -d "$tmpDir"

# Exit if unzipping failed
[[ $? -ne 0 ]] && echo "Could not unzip archive. Error Code: $?" && exit 1

# Make relocatable python framework
if [[ $reqChoice == "minimal" ]]; then
    echo "$reqMinimal" > "$tmpDir/reqs.txt"
    "$tmpDir/$repoName-master/make_relocatable_python_framework.py" --python-version "$pythonVersion" --destination "$reloPythonPkgRoot/frameworks" --pip-requirements="$tmpDir/reqs.txt"
elif [[ $reqChoice == "recommended" ]]; then
    echo "$reqRecommended" > "$tmpDir/reqs.txt"
    "$tmpDir/$repoName-master/make_relocatable_python_framework.py" --python-version "$pythonVersion" --destination "$reloPythonPkgRoot/frameworks" --pip-requirements="$tmpDir/reqs.txt"
fi

# Exit if relocatable python could not be created
[[ $? -ne 0 ]] && echo "Could not create Relocatable Python. Error Code: $?" && exit 1

# Rename the Python 3 framework to avoid naming conflict with future Python frameworks
/bin/mv "$reloPythonPkgRoot/frameworks/Python.framework" "$reloPythonPkgRoot/frameworks/python3.framework"

# Change ownership
/usr/sbin/chown -R root:wheel "$reloPythonPkgRoot"

# Create pkg
echo "Creating package"
createPostInstall
/usr/bin/pkgbuild --root "$reloPythonPkgRoot" --install-location "$mgmtPath" --scripts "$reloPythonPkgScript" "/Users/$loggedInUser/Desktop/MacAdmins-Python-$pythonVersion-$reqChoice-$(/bin/date "+%Y%m%d%H%M%S").pkg"

# Exit if pkg could not be created
[[ $? -ne 0 ]] && echo "Could not create pkg. Error Code: $?" && exit 1

# Clear temporary working directory
/bin/rm -rf "$tmpDir"