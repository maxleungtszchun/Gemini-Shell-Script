# Gemini Shell Script

A simple shell script for using Google Gemini in your terminal

This script only supports Mac OS at this moment.
It requires the installation of `jq` and `imagemagick`. You can install them by `brew install jq` and `brew install imagemagick`. This script will also install them for you if you have already installed `brew`.

Visit https://brew.sh/ for details about Homebrew.
Visit https://cloud.google.com/vertex-ai/docs/generative-ai/start/quickstarts/quickstart-multimodal#gemini-beginner-samples-drest for details about Google Gemini API

## Getting Started / Examples

### Text
```
./gemini.sh 'what is google gemini ai?'

./gemini.sh \
'Extract and summarize skills from the below paragraph in table format. First column of the table is skill name while the second column is skill type (hard vs soft).
Remove any verb and only keep noun. Do not miss any skills.

Bachelor’s degree in Mathematics, Information Engineering, Statistics, Marketing or other relevant disciplines
3+ years of relevant work experience in a similar function from a sizable company. Experience and interest in the travel and hospitality industry will be an advantage
Proficiency in scripting languages (SAS, SQL) is a must
Proficiency in data visualization tools (especially Tableau) is a must
Ability to write queries / programs and experience with R or Python will be an advantage
Experience with statistics modelling, such as decision tree, regression, clustering etc. will also be an advantage
A team player with strong time management skills and great attention to detail'
```

### Image
```
./gemini.sh 'what is it and how to make this?' 'https://storage.googleapis.com/generativeai-downloads/images/cake.jpg' 'image/jpeg'
./gemini.sh 'what is it and how to make this?' './cake.jpg' 'image/jpeg'
./gemini.sh 'what is it and how to make this?' 'gs://generativeai-downloads/images/cake.jpg' 'image/jpeg'
```

### Pdf
```
./gemini.sh 'give me a short summary in traditional chinese' '' '' 'https://upload.wikimedia.org/wikipedia/commons/1/1a/HKFactSheet_BasicLaw_122014.pdf'
./gemini.sh 'give me a short summary in english' '' '' './HKFactSheet_BasicLaw_122014.pdf'
```
Another example is to extract financial information from the annual report (in pdf) of listed companies.
