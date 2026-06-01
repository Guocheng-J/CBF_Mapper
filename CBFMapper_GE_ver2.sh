#!/bin/bash

# EMBRACE CBFMapper GE 3T pcASL scans 
# Version 2.0

# Author: Guocheng Jiang
# Version History
# 2.0: Use BASIL to estimate multi-PLD CBF than --wp mode, as the White Paper Mode (--wp) 
#      applies a fixed kinetic model (single-compartment model) with predefined parameters, 
#      that may only estimate a mean from 4 perfusion images as it assumes one delay and 
#      one fixed bolus duration.

# Input folder preparation:
# The input folder should contain the dcm images downloaded from GE scanner. For each PLD,
# the names should be "xx_3d_ax_asl_pldx".

# GJ's comment: Unfortunately the raw tag-control images were not available - This will be a strength for Siemens Prisma scanner
#               The script tried to avoid double quantification by assuming the perfusion maps created directly from GE Scanner
#               as pre-subtracted images, and use BASIL command to just conduct minimal model fitting: The output "relative" CBF
#               maps would be treated as an estimated absolute CBF maps since the unit has been set to ml/100g/min.
#               ATT can still be estimated and stored as "delttiss.nii.gz" in Step 1 of BASIL output.

# Future thoughts: 1. Whether the GE scanner can also output the raw tag-control pairs?
#                  2. To add the T1w data into the analysis. Since BASIL does not support the anatomical input directly, we need
#                     to manually conduct the FSL_ANAT operations. If we have raw tag-control pairs, we might be using oxford_asl
#                     directly to avoid extra steps.

# Version 2.0 last modified: March 13th 2025


############################################################################################
# Command line inputs
Subj=$1                # Folder containing raw images from GE Scanner
OutputDir=$2           # Identify an output folder
PatientID=$3           # Specify a patient ID

# Example input folder structure:
# 04-3d_ax_asl_pld1
# 05-3d_ax_asl_pld2  
# 06-3d_ax_asl_pld3
# 07-3d_ax_asl_pld4

# pcASL inputs

BolusDuration=1.8
PLD1=1.025             # Note: If you want to add a 5th PLD, you will need to define a 
PLD2=1.525             #       PLD5 variable here, and also define --pld5 under Step 1.1
PLD3=2.025             #       cat <<EOF > EMBD_Basil_param.txt
PLD4=2.525
NumRpts=1              # If 2+ repeats, order the 4D nifti PLD as: 1,2,3..,1,2,3..

# Which column in json describes the post label delay?
NamePLDJSON="InversionTime"


############################################################################################
# Step 1: Creating analysis directory and image reconstructions
#    1.1: Create an analysis output folder
#    1.2: Create a BASIL parameter input file
#    1.3: Unzip the dicom images (optional)
#    1.4: Convert dicom to NifTI

echo "Step 1: Creating analysis directory for patient: ${PatientID}"

# 1.1 Creating patient output directory
mkdir ${OutputDir}/EMBD_CBFAnalysis
mkdir ${OutputDir}/EMBD_CBFAnalysis/${PatientID}
echo "  >> 1.1 Patient directory created."

# 1.2 Create a BASIL parameter input file:
cat <<EOF > ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/EMBD_Basil_param.txt
--casl
--bolus=${BolusDuration}
--pld1=${PLD1} --pld2=${PLD2} --pld3=${PLD3} --pld4=${PLD4}
--repeats=${NumRpts}
EOF

echo "  >> 1.2 BASIL Parameter file generated."

# 1.3 Check if there are any .zip files in the directory
if ls "${Subj}"/*.zip 1> /dev/null 2>&1; then
   
    # If found zip files, loop through each zip file and unzip it
    for file in "${Subj}"/*.zip; do
        unzip -q "$file" -d "${Subj}"
        echo "  >> 1.3 Images are zipped, unzipping"
    done

else
    echo "  >> 1.3 There is no zip files, skipping"
fi


# 1.4 Record the data path for each PLD.
find ${Subj} -type d -name "*asl_pld*" > ${Subj}/asl_loc.txt
asl_img=${Subj}/asl_loc.txt

echo "  >> 1.4 Data paths for each PLD has been located."

# 1.5 DICOM to NIFTI using dcm2niix.
echo "  Diagnostic output from dcm2niix:
      #######################################################
          
          
          "
for i in $(cat $asl_img); do

  dcm2niix ${i} 
  cp ${i}/*.nii ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/
  cp ${i}/*.json ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/
  rm ${i}/*.nii
  rm ${i}/*.json

done
echo "

     #######################################################
         End of dcm2niix diagnostic data  "

############################################################################################
# Step 2: Data naming, sorting and preprocessing. Since no T1w image was available in the
#         phantom scan, I used M0 images for skull stripping.
#    2.1: Identify the perfusion images and their PLDs
#    2.2: Identify the corresponding M0 images.
#    2.3: BET the M0 image to create a brain mask.
#    2.4: Merge the CBF maps and perform motion correction.
#    2.5: Merge the M0 images.

echo "Step 2: Identifying perfusion images versus M0 images and their PLDs"

# 2.1 Initiate a dictionary to store the perfusion-to-PLD data.
declare -A PLD_MAPPING  # Dictionary to store Perfusion-to-PLD mapping

echo "  >> 2.1 Identifying perfusion images"
# First Pass: Process Perfusion images first
for json_file in ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/*.json; do
    nii_file="${json_file%.json}.nii"

    # Read ImageType from JSON
    ImgType=$(jq -r '.ImageType[]' "$json_file" | grep -i "PERFUSION" &> /dev/null && echo "Perfusion" || echo "M0")

    # If Perfusion, extract PLD
    if [[ "$ImgType" == "Perfusion" ]]; then
        PLD=$(jq -r ".${NamePLDJSON}" "$json_file")

        # Determine PLD number
        if (( $(echo "$PLD == $PLD1" | bc -l) )); then
            PLD_Num=1
        elif (( $(echo "$PLD == $PLD2" | bc -l) )); then
            PLD_Num=2
        elif (( $(echo "$PLD == $PLD3" | bc -l) )); then
            PLD_Num=3
        elif (( $(echo "$PLD == $PLD4" | bc -l) )); then
            PLD_Num=4
        else
            echo "  >> 2.1 Warning: Unknown PLD value ($PLD) for $json_file"
            continue
        fi

        # Standardize perfusion filename: Remove trailing "a" if it exists
        base_name="${nii_file%.nii}"
        standardized_base="${base_name%a}"  # Remove trailing 'a'

        # Store Perfusion image PLD in dictionary (base name -> PLD_Num)
        PLD_MAPPING["$standardized_base"]="$PLD_Num"

        # Debug: Print stored PLD mapping
        #echo "  >> 2.1 Stored: ${standardized_base} -> PLD ${PLD_Num}"

        # Rename Perfusion files
        new_json="Perfusion_${PLD_Num}.json"
        new_nii="Perfusion_${PLD_Num}.nii"
        mv "$json_file" "${OutputDir}/EMBD_CBFAnalysis/${PatientID}/$new_json"
        mv "$nii_file" "${OutputDir}/EMBD_CBFAnalysis/${PatientID}/$new_nii"

    fi
done


echo "  >> 2.2 Identifying M0 images"
# Second Pass: Process M0 images
for json_file in ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/*.json; do
    nii_file="${json_file%.json}.nii"

    # Read ImageType from JSON
    ImgType=$(jq -r '.ImageType[]' "$json_file" | grep -i "PERFUSION" &> /dev/null && echo "Perfusion" || echo "M0")

    if [[ "$ImgType" == "M0" ]]; then
        base_name="${nii_file%.nii}"
        perf_base="${base_name%a}"  # Remove trailing 'a' to match perfusion base name

        # Get corresponding PLD from Perfusion mapping
        PLD_Num=${PLD_MAPPING["$perf_base"]}

        if [[ -z "$PLD_Num" ]]; then
            echo "  >> 2.2 Warning: No matching Perfusion image found for M0 image $json_file"
            continue
        fi
        
        # Rename M0 files
        new_json="M0_${PLD_Num}.json"
        new_nii="M0_${PLD_Num}.nii"
        mv "$json_file" "${OutputDir}/EMBD_CBFAnalysis/${PatientID}/$new_json"
        mv "$nii_file" "${OutputDir}/EMBD_CBFAnalysis/${PatientID}/$new_nii"

    fi
done

# If T1w data is not available, use PDw image to create brain masks.
# 2.3 BET the M0 brain and mask the individual CBF images:
echo "  >> 2.3 Skull stripping on the individual CBF images"

# Loop through M0 images
for m0_file in ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/M0_*.nii; do
    # Extract the base name without extension
    base_name="${m0_file%.nii}"

    # Determine the corresponding Perfusion file
    perf_file="${base_name/M0/Perfusion}.nii"

    # Step 1: Skull Strip M0 image and generate brain mask
    echo "     Skull stripping: $m0_file"
    bet "$m0_file" "${base_name}_brain.nii.gz" -m
    
    # The mask file will be named: M0_X_brain_mask.nii.gz
    mask_file="${base_name}_brain_mask.nii.gz"

    # Step 2: Apply the mask to the corresponding Perfusion image
    if [[ -f "$perf_file" ]]; then
        #echo "    Applying mask: $mask_file to $perf_file"
        fslmaths "$perf_file" -mas "$mask_file" "${perf_file%.nii}_masked.nii.gz"
    else
        echo "     Warning: Corresponding Perfusion file ($perf_file) not found!"
    fi
done

# 2.4 Merge the CBF Maps and motion correction.
echo "  >> 2.4 Merging CBF Maps"
fslmerge -t ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Perfusion_*_masked.nii.gz
fslmaths ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz -div 10 ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz
mcflirt -in ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz -out ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion_mc.nii.gz

# 2.5 Merged M0 maps
echo "  >> 2.5 Merging M0 Maps"
fslmerge -t ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Mzero.nii.gz ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/M0_*.nii


############################################################################################
# Step 3: CBF perfusion quantification using Oxford ASL and different methods:
#    3.1: Use BASIL command directly, avoid double quantification
#    3.2: Use Oxford_asl white paper mode - Diagnostic - Since WP mode seems only supports
#         single PLD analysis
#    3.3: Just create an average of the 4 PLD images to serve as a diagnostic QC reference. 


echo "Step 3: Estimating CBF using BASIL"
basil -i ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz        \
      -o ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/CBFAnalysis_BASIL              \
      -@ ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/EMBD_Basil_param.txt --spatial

cp ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/CBFAnalysis_BASIL/step1/mean_ftiss.nii.gz ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/0_CBF_BASIL.nii.gz
cp ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/CBFAnalysis_BASIL/step2/mean_ftiss.nii.gz ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/0_CBF_BASIL_smoothed.nii.gz

echo "Step 3: Diagnostic: Estimating CBF using WP mode"
oxford_asl -i ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion.nii.gz               \
           -o ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/CBFAnalysis_WP                       \
           --casl --bolus=${BolusDuration} --tis=2.825,3.325,3.825,4.325 --mc --spatial --wp

cp ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/CBFAnalysis_WP/native_space/perfusion.nii.gz ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/0_CBF_WP.nii.gz

echo "Step 3: Just compute a mean"
fslmaths ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/Merged_Perfusion_mc.nii.gz -Tmean ${OutputDir}/EMBD_CBFAnalysis/${PatientID}/0_CBF_Tmean.nii.gz

# GJ's comment: Unfortunately the raw tag-control images were not available - This will be a strength for Siemens Prisma scanner
#               The script tried to avoid double quantification by assuming the perfusion maps created directly from GE Scanner
#               as pre-subtracted images, and use BASIL command to just conduct minimal model fitting: The output "relative" CBF
#               maps would be treated as an estimated absolute CBF maps since the unit has been set to ml/100g/min.
#               ATT can still be estimated and stored as "delttiss.nii.gz" in Step 1 of BASIL output.

# Future thoughts: 1. Whether the GE scanner can also output the raw tag-control pairs?
#                  2. To add the T1w data into the analysis. Since BASIL does not support the anatomical input directly, we need
#                     to manually conduct the FSL_ANAT operations. If we have raw tag-control pairs, we might be using oxford_asl
#                     directly to avoid extra steps.

# Version 2.0 last modified: March 13th 2025



