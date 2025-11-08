from google.cloud import dlp_v2

client  = dlp_v2.DlpServiceClient()
parent  = f"projects/petproject-test-g"
inspect_config = {
    "info_types": [{"name": "PHONE_NUMBER"}, {"name": "EMAIL_ADDRESS"}],
    "min_likelihood": dlp_v2.Likelihood.POSSIBLE,
}
item = {"value": "My email is foo@example.com and phone is 9991234567."}
response = client.inspect_content(
    request={"parent": parent, "inspect_config": inspect_config, "item": item}
)
print("Findings:")
for f in response.result.inspect_result.findings:
    print(f"  {f.info_type.name} — {f.likelihood.name}")
