Name: domain-diag
Version: 0.2.3
Release: alt1

Summary: Active Directory domain environment diagnostic tool
License: GPLv3
Group: System/Configuration/Other
BuildArch: noarch

Url: https://gitea.basealt.ru/saratov/domain-diag

Source: %name-%version.tar

BuildRequires: shellcheck

%description
Active Directory domain environment diagnostic tool.

%prep
%setup -q

%build
sed -i 's/^VERSION=.*/VERSION=%version/' domain-diag

%install
install -p -D -m755 %name %buildroot%_bindir/%name

%check
shellcheck -e SC1090,SC1091,SC2004,SC2015,SC2034,SC2086,SC2154,SC2001,SC2120,SC2119 %name

%files
%_bindir/%name

%changelog
* Wed Apr 19 2023 Andrey Limachko <liannnix@altlinux.org> 0.2.3-alt1
- Fixed script return codes
- Fixed nothing to grep bug
- Added resolv.conf search multidomain support
- Fixed script failure when default_realm commented in krb5.conf

* Tue Jan 10 2023 Andrey Limachko <liannnix@altlinux.org> 0.2.2-alt1
- Added kinit from system keytab when run as root
- Fixed ldapsearch timeout limit

* Wed Dec 21 2022 Andrey Limachko <liannnix@altlinux.org> 0.2.1-alt1
- Initial build

