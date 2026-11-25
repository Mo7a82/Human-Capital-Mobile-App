# Human-Capital-Mobile-App

These are the integration files for a proof of concept of a Human Capital mobile app for the Organization, built in 2015. Employees could use the app to sign in, view their profile, request vacation, track requests and check their vacation balance. Managers could approve or reject requests. All of it ran against Oracle E-Business Suite (EBS) HRMS.

The app was built with Oracle Mobile Application Framework (OMAF) in Java. It talked to EBS through SOAP web services, which Oracle's Integrated SOA Gateway generated from standard and custom PL/SQL APIs.

This repository holds the back-end integration work: the SoapUI test project, sample requests and responses for each service, and a step-by-step guide to publishing a custom PL/SQL package as a web service. The OMAF app source isn't included.

## Repository layout

```
Human-Capital-Mobile-App/
├── Create Custom WS.docx                    # Guide: publish a custom PL/SQL API as a SOAP service
└── SOAPUI webservices/
    ├── apps-vis-soapui-project.xml          # SoapUI project with all three service bindings
    ├── VALIDATE_LOGIN/
    │   ├── URL.txt                          # Endpoint
    │   ├── request.xml                      # Sample request
    │   └── response.xml                     # Sample response
    └── CREATE_ABSCENCE_API/
        ├── URL.txt
        ├── request.xml
        └── response.xml
```

## Architecture

```mermaid
flowchart LR
    A[OMAF mobile app<br/>Java] -->|SOAP over HTTP| B[Oracle Integrated SOA Gateway]
    B --> C[FND_WEB_SEC<br/>login check]
    B --> D[HR_PERSON_ABSENCE_API<br/>create, update, delete absence]
    B --> E[FND_USER_PKG<br/>user maintenance]
    B --> F[Custom PL/SQL packages<br/>profile, balance, worklist]
    C & D & E & F --> G[(Oracle EBS HRMS)]
```

Each SOAP call carries an `SOAHeader` that sets the EBS session context: responsibility, application, security group, NLS language and org ID. For example, the login check runs as `SYSTEM_ADMINISTRATOR` / `SYSADMIN`, and the absence API runs as an HRMS manager responsibility in the `PER` application.

## Services

| Binding | Operations in the SoapUI project | Used for |
|---|---|---|
| `FND_WEB_SEC_Binding` | `VALIDATE_LOGIN` | Signing in with EBS user name and password |
| `HR_PERSON_ABSENCE_API_Binding` | `CREATE_PERSON_ABSENCE`, `UPDATE_PERSON_ABSENCE`, `DELETE_PERSON_ABSENCE` | Submitting and managing vacation requests |
| `FND_USER_PKG_Binding` | `VALIDATE_USER_NAME`, `CHANGE_USER_NAME`, `LDAP_WRAPPER_CREATE_USER`, `LDAP_WRAPPER_UPDATE_USER`, `DERIVE_PERSON_PARTY_ID` and 7 more | User account checks and maintenance |

### Login

`VALIDATE_LOGIN` takes `P_USER` and `P_PWD` and returns `Y` or `N`:

```xml
<OutputParameters>
   <VALIDATE_LOGIN>Y</VALIDATE_LOGIN>
</OutputParameters>
```

### Create a vacation request

`CREATE_PERSON_ABSENCE` takes the person, business group, absence type, start and end dates, and number of days:

```xml
<cre:P_VALIDATE>0</cre:P_VALIDATE>
<cre:P_EFFECTIVE_DATE>2015-03-02T00:00:00</cre:P_EFFECTIVE_DATE>
<cre:P_PERSON_ID>18701</cre:P_PERSON_ID>
<cre:P_BUSINESS_GROUP_ID>5461</cre:P_BUSINESS_GROUP_ID>
<cre:P_ABSENCE_ATTENDANCE_TYPE_ID>932</cre:P_ABSENCE_ATTENDANCE_TYPE_ID>
<cre:P_DATE_START>2015-03-02T00:00:00</cre:P_DATE_START>
<cre:P_DATE_END>2015-03-02T00:00:00</cre:P_DATE_END>
<cre:P_ABSENCE_DAYS>1</cre:P_ABSENCE_DAYS>
```

The response returns the new `P_ABSENCE_ATTENDANCE_ID` and object version number. It also returns the API's warning flags, such as overlapping absences or exceeding the PTO entitlement. The app can show those flags to the employee.

## Publishing a custom PL/SQL API as a web service

`Create Custom WS.docx` covers the steps with screenshots. In short:

1. Write the PL/SQL package and add the annotation comments the Integration Repository needs.
2. Register the package in the Integration Repository and load it.
3. Open the package in Integrated SOA Gateway, select the procedure and click Create Grant.
4. Click Generate WSDL, choose Username Token authentication and click Deploy.
5. Open View WSDL and save it as an XML file.
6. In SoapUI, create a new project from that WSDL and test the call.
7. If the call fails, check the SOA Monitor for details. A known fix is to download the generated WSDL from the server, remove the `IRepOverloadSeq` line, upload it back to the same location and call again.

## Testing with SoapUI

1. Install [SoapUI](https://www.soapui.org/) 5.x.
2. Import `SOAPUI webservices/apps-vis-soapui-project.xml`.
3. Change the endpoint host in each binding to your EBS instance. The samples point to an Oracle Vision demo instance on port 8000.
4. Set the WS-Security username token on the request to an EBS user who has the right responsibility.
5. Run the request and compare it with the sample response in the matching folder.

## Tech stack

Oracle E-Business Suite R12 HRMS, Oracle Integrated SOA Gateway, PL/SQL, SOAP and XML, SoapUI, Java and Oracle Mobile Application Framework.

## Notes

- The guide refers to a `Session Action Script.txt` file for registering packages, but that file isn't in the repository.
- The `CREATE_ABSCENCE_API` folder name has a typo ("ABSCENCE"). The API itself is `HR_PERSON_ABSENCE_API`.
- The sample requests use Oracle Vision demo data and credentials. Never commit real EBS user names, passwords or employee IDs.

## Outcome

The proof of concept covered sign-in, the employee profile, new vacation requests, the request worklist, the manager's approve or reject view and the vacation balance. EJADA was awarded the full HCM mobile app project after it.
