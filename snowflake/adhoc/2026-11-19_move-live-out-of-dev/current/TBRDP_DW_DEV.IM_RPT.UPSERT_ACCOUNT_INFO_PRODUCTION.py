
import _snowflake
import requests
import json
import pandas as pd
import csv

def main(session):
    try:
        # Salesforce REST API version - single place to change
        API_VERSION = 'v56.0'

        # ------------------------------------------------------------------
        # Credentials from Snowflake secret.
        #
        # Expected secret JSON shape for the External Client App:
        # {
        #   "client_id":     "<Consumer Key from the External Client App>",
        #   "client_secret": "<Consumer Secret from the External Client App>",
        #   "token_url":     "https://tbrcrm.my.salesforce.com/services/oauth2/token"
        # }
        #
        # NOTE: username, password and security_token are no longer needed.
        # ------------------------------------------------------------------
        secret_str = _snowflake.get_generic_secret_string('sf_creds')
        creds = json.loads(secret_str)

        token_url = creds['token_url']

        # ------------------------------------------------------------------
        # Client Credentials grant.
        #
        # This replaces the username-password grant used by the old Connected
        # App. External Client Apps do not support grant_type='password'.
        # The "Run As" user is configured on the app itself, under
        # Policies -> OAuth Policies, not sent from here.
        # ------------------------------------------------------------------
        payload = {
            'grant_type': 'client_credentials',
            'client_id': creds['client_id'],
            'client_secret': creds['client_secret']
        }
        token_headers = {'Content-Type': 'application/x-www-form-urlencoded'}

        response = requests.post(token_url, data=payload, headers=token_headers, timeout=60)
        if response.status_code != 200:
            return f"Token error ({response.status_code}): {response.text}"

        token_data = response.json()

        access_token = token_data.get('access_token')
        if not access_token:
            return f"Token error: no access_token in response: {response.text}"

        # instance_url is normally returned; fall back to the token host if absent.
        instance_url = token_data.get('instance_url') or token_url.split('/services/')[0]

        headers = {"Authorization": f"Bearer {access_token}", "Content-Type": "application/json"}

        # ------------------------------------------------------------------
        # Everything below this point is unchanged from the original
        # procedure apart from API_VERSION being substituted for the
        # hardcoded v56.0 in the five REST URLs.
        # ------------------------------------------------------------------

        # Query Snowflake data with error handling
        try:
            snowflake_data = pd.DataFrame(session.sql("""
                SELECT 
                    V_ODS_GCP_TDC_PATRON_CONTACT.PATRON_ACCOUNT_ID,
                    V_ODS_GCP_TDC_PATRON_CONTACT.FIRST_NAME, 
                    V_ODS_GCP_TDC_PATRON_CONTACT.MIDDLE_NAME, 
                    V_ODS_GCP_TDC_PATRON_CONTACT.LAST_NAME, 
                    CAST(DATE_OF_BIRTH AS DATE) AS DATE_OF_BIRTH,
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_EMAIL_LAST_EMAIL.EMAIL, 
                    CONCAT(
                        COALESCE(V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.ADDR1, ''), 
                        ' ', 
                        COALESCE(V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.ADDR2, '')
                    ) AS ADDR1, 
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.CITY, 
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.SUB_COUNTRY_CODE, 
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.SUB_COUNTRY_NAME,
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.POSTAL_CODE, 
                    V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.COUNTRY_CODE, 
                    PHONE_NUMBER, 
                    PATRON_ACCOUNT_NAME,
                    V_ODS_GCP_TDC_PATRON_ACCOUNT_TYPE.DESCRIPTION AS PATRON_ACCOUNT_TYPE, 
                    V_ODS_GCP_TDC_PATRON_ACCOUNT_TYPE.PATRON_ACCOUNT_TYPE_CODE, 
                    ID
                FROM TBRDP_DW_PROD.IM_RPT.V_ODS_GCP_TDC_PATRON_CONTACT
                INNER JOIN TBRDP_DW_PROD.IM_RPT.V_ODS_GCP_TDC_PATRON_ACCOUNT
                    ON V_ODS_GCP_TDC_PATRON_CONTACT.PATRON_ACCOUNT_ID = V_ODS_GCP_TDC_PATRON_ACCOUNT.PATRON_ACCOUNT_ID
                LEFT JOIN TBRDP_DW_PROD.IM_RPT.V_ODS_GCP_TDC_PATRON_ACCOUNT_TYPE
                    ON V_ODS_GCP_TDC_PATRON_ACCOUNT.PATRON_ACCOUNT_TYPE_CODE = V_ODS_GCP_TDC_PATRON_ACCOUNT_TYPE.PATRON_ACCOUNT_TYPE_CODE
                LEFT JOIN TBRDP_DW_PROD.IM_RPT.V_SBL_ODS_GCP_TDC_PATRON_CONTACT_EMAIL_LAST_EMAIL
                    ON V_ODS_GCP_TDC_PATRON_CONTACT.PATRON_ACCOUNT_ID = 
                       V_SBL_ODS_GCP_TDC_PATRON_CONTACT_EMAIL_LAST_EMAIL.PATRON_ACCOUNT_ID
                LEFT JOIN TBRDP_DW_PROD.IM_RPT.V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS
                    ON V_ODS_GCP_TDC_PATRON_CONTACT.PATRON_ACCOUNT_ID = 
                       V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.PATRON_ACCOUNT_ID
                LEFT JOIN TBRDP_DW_PROD.IM_RPT.V_SBL_ODS_GCP_TDC_PATRON_CONTACT_PHONE_LAST_PHONE
                    ON V_ODS_GCP_TDC_PATRON_CONTACT.PATRON_ACCOUNT_ID = 
                       V_SBL_ODS_GCP_TDC_PATRON_CONTACT_PHONE_LAST_PHONE.PATRON_ACCOUNT_ID
                LEFT JOIN TBRDP_DW_PROD.IM_RPT.V_ODS_GCP_TDC_PATRON_ORDER
                    ON V_ODS_GCP_TDC_PATRON_ACCOUNT.PATRON_ACCOUNT_ID = V_ODS_GCP_TDC_PATRON_ORDER.FINANCIAL_PATRON_ACCOUNT_ID
                LEFT JOIN FIVETRAN_DATABASE.SALESFORCE_CRM.CONTACT
                    ON V_SBL_ODS_GCP_TDC_PATRON_CONTACT_EMAIL_LAST_EMAIL.EMAIL = CONTACT.EMAIL
                WHERE (
                    V_ODS_GCP_TDC_PATRON_CONTACT.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                    OR V_ODS_GCP_TDC_PATRON_ACCOUNT.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                    OR V_SBL_ODS_GCP_TDC_PATRON_CONTACT_EMAIL_LAST_EMAIL.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                    OR V_SBL_ODS_GCP_TDC_PATRON_CONTACT_ADDRESS_LAST_ADDRESS.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                    OR V_SBL_ODS_GCP_TDC_PATRON_CONTACT_PHONE_LAST_PHONE.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                    OR V_ODS_GCP_TDC_PATRON_ORDER.LAST_UPDATED_DATE >= DATEADD(MINUTE, -120, CURRENT_TIMESTAMP)
                )
                AND V_ODS_GCP_TDC_PATRON_CONTACT.PRIMARY = 1
                GROUP BY ALL
            """).collect())
        except Exception as query_error:
            return f"Query execution failed: {str(query_error)}"
        
        # Validate and prepare data
        if not snowflake_data.empty and 'PATRON_ACCOUNT_ID' in snowflake_data.columns:
            snowflake_data['PATRON_ACCOUNT_ID'] = snowflake_data['PATRON_ACCOUNT_ID'].fillna(0).astype(int)
            snowflake_data['ID'] = snowflake_data['ID'].fillna('').astype(str)
            # Properly handle DATE_OF_BIRTH - convert to string only if not null
            snowflake_data['DATE_OF_BIRTH'] = snowflake_data['DATE_OF_BIRTH'].astype(str).where(
                snowflake_data['DATE_OF_BIRTH'].notnull(), None
            )
        else:
            snowflake_data = pd.DataFrame(columns=[
                'PATRON_ACCOUNT_ID', 'FIRST_NAME', 'MIDDLE_NAME', 'LAST_NAME', 'DATE_OF_BIRTH', 
                'EMAIL', 'ADDR1', 'CITY', 'SUB_COUNTRY_CODE', 'SUB_COUNTRY_NAME', 'POSTAL_CODE',
                'COUNTRY_CODE', 'PHONE_NUMBER', 'PATRON_ACCOUNT_NAME', 'PATRON_ACCOUNT_TYPE', 
                'PATRON_ACCOUNT_TYPE_CODE', 'ID'
            ])
        
        # If no data to process, return early
        if snowflake_data.empty:
            return "No rows to process - no updates in the last 120 minutes"
        
        log_entries = []
        
        # Iterate over rows from the Snowflake data
        for index, row in snowflake_data.iterrows():
            try:
                # Replace NaN values with None to avoid JSON parsing errors
                row = row.where(pd.notna(row), None)
                
                # Create a dictionary of non-null fields only
                data = {}
                field_mapping = {
                    'LAST_NAME': 'LastName',
                    'FIRST_NAME': 'FirstName',
                    'MIDDLE_NAME': 'MiddleName',
                    'DATE_OF_BIRTH': 'PersonBirthdate',
                    'ADDR1': 'PersonMailingStreet',
                    'CITY': 'PersonMailingCity',
                    'SUB_COUNTRY_NAME': 'PersonMailingState',
                    'COUNTRY_CODE': 'PersonMailingCountry',
                    'POSTAL_CODE': 'PersonMailingPostalCode',
                    'PHONE_NUMBER': 'Phone',
                    'EMAIL': 'PersonEmail',
                    'PATRON_ACCOUNT_NAME': 'PV_Account_Name__c',
                    'PATRON_ACCOUNT_TYPE': 'PV_Account_Type__c',
                    'PATRON_ACCOUNT_ID': 'Primary_Account_Number__c'
                }
                
                for sf_field, crm_field in field_mapping.items():
                    # Only include fields that are not None and handle DATE_OF_BIRTH specially
                    if row[sf_field] is not None:
                        # Skip if it's a date field and the value is None, "None", or "nan"
                        if sf_field == 'DATE_OF_BIRTH' and str(row[sf_field]).lower() in ['none', 'nan', '']:
                            continue
                        data[crm_field] = row[sf_field]
                
                # First, try to find account by PATRON_ACCOUNT_ID
                patron_id_search_url = f"{instance_url}/services/data/{API_VERSION}/query/?q=SELECT+Id+FROM+Account+WHERE+Primary_Account_Number__c='{row['PATRON_ACCOUNT_ID']}'"
                patron_search_response = requests.get(patron_id_search_url, headers=headers)
                
                account_found = False
                account_id = None
                
                if patron_search_response.status_code == 200:
                    patron_result = patron_search_response.json()
                    if patron_result['totalSize'] > 0:
                        account_id = patron_result['records'][0]['Id']
                        account_found = True
                
                # If not found by PATRON_ACCOUNT_ID, try email
                if not account_found and row['EMAIL']:
                    email_search_url = f"{instance_url}/services/data/{API_VERSION}/query/?q=SELECT+Id+FROM+Account+WHERE+PersonEmail='{row['EMAIL']}'"
                    email_search_response = requests.get(email_search_url, headers=headers)
                    
                    if email_search_response.status_code == 200:
                        email_result = email_search_response.json()
                        if email_result['totalSize'] > 0:
                            account_id = email_result['records'][0]['Id']
                            account_found = True
                
                if account_found:
                    # Get current account data
                    get_account_url = f"{instance_url}/services/data/{API_VERSION}/sobjects/Account/{account_id}"
                    current_account = requests.get(get_account_url, headers=headers).json()
                    
                    # Only update fields that are not null in snowflake_data
                    update_data = {}
                    for field, value in data.items():
                        if value is not None:
                            update_data[field] = value
                    
                    if update_data:
                        update_url = f"{instance_url}/services/data/{API_VERSION}/sobjects/Account/{account_id}"
                        update_response = requests.patch(update_url, headers=headers, data=json.dumps(update_data))
                        
                        if update_response.status_code == 204:
                            print(f"Updated Account {account_id}")
                            log_entries.append({
                                'Action': 'Update',
                                'Account_ID': account_id,
                                'Email': row['EMAIL'] if row['EMAIL'] else '',
                                'Updated_Fields': ', '.join(update_data.keys()),
                                'Created_Fields': '',
                                'Error_Message': ''
                            })
                        else:
                            print(f"Error updating Account {account_id}: {update_response.text}")
                            log_entries.append({
                                'Action': 'Error',
                                'Account_ID': account_id,
                                'Email': row['EMAIL'] if row['EMAIL'] else '',
                                'Updated_Fields': '',
                                'Created_Fields': '',
                                'Error_Message': update_response.text[:500]  # Limit error message length
                            })
                else:
                    # Account doesn't exist, create it
                    create_url = f"{instance_url}/services/data/{API_VERSION}/sobjects/Account/"
                    create_response = requests.post(create_url, headers=headers, data=json.dumps(data))
                    
                    if create_response.status_code == 201:
                        new_account_id = create_response.json()['id']
                        print(f"Created New Account {new_account_id}")
                        log_entries.append({
                            'Action': 'Create',
                            'Account_ID': new_account_id,
                            'Email': row['EMAIL'] if row['EMAIL'] else '',
                            'Updated_Fields': '',
                            'Created_Fields': ', '.join(data.keys()),
                            'Error_Message': ''
                        })
                    else:
                        print(f"Error creating Account: {create_response.text}")
                        log_entries.append({
                            'Action': 'Error',
                            'Account_ID': '',
                            'Email': row['EMAIL'] if row['EMAIL'] else '',
                            'Updated_Fields': '',
                            'Created_Fields': '',
                            'Error_Message': create_response.text[:500]  # Limit error message length
                        })
                        
            except Exception as e:
                print(f"Error processing row: {e}")
                log_entries.append({
                    'Action': 'Error',
                    'Account_ID': '',
                    'Email': row['EMAIL'] if row['EMAIL'] and pd.notna(row['EMAIL']) else '',
                    'Updated_Fields': '',
                    'Created_Fields': '',
                    'Error_Message': str(e)[:500]  # Limit error message length
                })
        
        # Write to Log table using DataFrame (bulk insert approach)
        if log_entries:
            try:
                # Convert log entries to DataFrame
                log_df = pd.DataFrame(log_entries)
                
                # Ensure all required columns exist with default values
                required_columns = ['Action', 'Account_ID', 'Email', 'Updated_Fields', 'Created_Fields', 'Error_Message']
                for col in required_columns:
                    if col not in log_df.columns:
                        log_df[col] = ''
                
                # Replace None with empty string for all columns
                log_df = log_df.fillna('')
                
                # Convert to Snowpark DataFrame
                sp_log_df = session.create_dataframe(log_df[required_columns])
                
                # Add created_at column with current timestamp
                from snowflake.snowpark.functions import current_timestamp
                sp_log_df = sp_log_df.with_column("created_at", current_timestamp())
                
                # Write to table
                sp_log_df.write.mode("append").save_as_table(
                    "TBRDP_DW_DEV.LOAD.ACCOUNT_UPSERT_LOG_PRODUCTION"
                )
                
                # Count successes and failures
                success_count = len([e for e in log_entries if e['Action'] in ['Update', 'Create']])
                error_count = len([e for e in log_entries if e['Action'] == 'Error'])
                
                return f"Processed {len(snowflake_data)} rows: {success_count} successful, {error_count} errors. Logged {len(log_entries)} entries."
                
            except Exception as log_error:
                return f"Processing completed ({len(snowflake_data)} rows) but logging failed: {str(log_error)}"
        else:
            return f"Processed {len(snowflake_data)} rows with no log entries"
            
    except Exception as main_error:
        return f"Main procedure error: {str(main_error)}"

