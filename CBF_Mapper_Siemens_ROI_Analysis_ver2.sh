
#!/bin/bash

# CBF Mapper v2: Adapted for the EXACT project.
# You can treat this program as the original CBFMapper + a cortex ROI analysis tool
# It produces the CBF map as the previous script, but also carry out ROI analysis.

# This script analyse the CBF under a standard space of Harvard-Oxford atlas.
# Input will be a list of paths of each subject.
# Output includes: 1. Calibrated CBF Map, 2. Segmented T1 and CBF images, 3. Estimated mean and median CBF values.

# The following items must be present in the same folder of the script to make it functional:
# 1. The Atlas: HarvardOxford-cort-maxprob-thr25-2mm.nii.gz
# 2. The atlas index-to-ROI lookup table: Atlas_lookup_table.csv

# Author: Guocheng Jiang
# Version: v2.1
# Change log:
# V1.0: Adds the ROI analysis to the original CBF Mapper, and it passed the test run
# V2.0: Adds the ROI analysis for the cortex GM CBF. It also adds a PNG QC feature!
# V2.1: Fixed a bug as some ASL image has "Ox" at the image file name.
# V2.2: Melissa fixed the bug on lines 171-172 and 255-256 so that the script runs on the current version of FSL.
# She also modified the script to accept different file names (scans from the
# MOVE-IT MRS (sub-cad##), MOVE-IT (sub-mv##), and EXPRESS-V (sub-ev##) studies).
# V2.3: Melissa modified the script to reflect the 8 T-C pairs and changed .IMA to .dcm to reflect newer
# EXPRESS-V scans. Edited oxford_asl line to remove WMH conversion.

# Syntax to call the script:
# bash EXACT_CBF_Analyser_v2.2.sh <TXT file of subject list> <The path of where the MRI data are in>

# The folder containing MRI data should be the raw DICOM data which can be directly downloaded from Siemens Prisma MRI.
# You don't need do anything for preprocessing : )
####################################################################################################

# Input: 
subj_list=$1        # The txt file of a list of subject MRI directory paths.
master_dir=$2       # The path of the folder containing all participants.

####################################################################################################
# Create a master analysis directory.

mkdir EXACT_CBF_Analysis
mkdir EXACT_CBF_Analysis/0_PNG_Image_QC     

# Create two master csv files to save mean and median results from template 

cp Atlas_lookup_table.csv EXACT_CBF_Analysis/CBF_ROI_Analysis_Results_Mean.csv
cp Atlas_lookup_table.csv EXACT_CBF_Analysis/CBF_ROI_Analysis_Results_Median.csv
cp Atlas_lookup_table.csv EXACT_CBF_Analysis/GM_only_CBF_ROI_Analysis_Results_Mean.csv
cp Atlas_lookup_table.csv EXACT_CBF_Analysis/GM_only_CBF_ROI_Analysis_Results_Median.csv


# Create a master csv file to save the mean global GM CBF vs. WM CBF
echo "Patient_ID, Mean_CBF_GM, Mean_CBF_WM"> EXACT_CBF_Analysis/CBF_Global_GM_WM_Analysis_Results.csv

# Loop to create a folder for each participant

for subj in $(cat $subj_list); do 
  
  #######################################################################################
  # Step 1: Creating analysis directory for each participant 
  
  echo "#################################################################################"
  echo "Working on participant: ${subj}"    
  echo "  - Step 1: Create analysis directory"                                    
  echo "       >> Identifying T1w and ASL image files"
  
  # Extract the patient name from the last "/"
  patient_name="${subj##*/}"
           
  # Create a folder for individual patient
  mkdir EXACT_CBF_Analysis/${patient_name}             
  
  # Copy the T1w image to the analysis directory
  echo "       >> Copying T1w image"
  cp -r ${master_dir}/${subj}/anat EXACT_CBF_Analysis/${patient_name}/T1w
  
  # Copy the ASL image to the analysis directory
  echo "       >> Copying ASL image"
  cp -r ${master_dir}/${subj}/perf EXACT_CBF_Analysis/${patient_name}/ASL
  
  # Convert the DICOM images to the NIFTI files
  echo "       >> Converting DICOM to NIFTI"
  echo "========================================================================="
  echo "Diagnostic message from dcm2niix"   
  echo " "
  dcm2niix EXACT_CBF_Analysis/${patient_name}/T1w
  dcm2niix EXACT_CBF_Analysis/${patient_name}/ASL
  mv EXACT_CBF_Analysis/${patient_name}/T1w/T1w_t1_mprage_*.nii EXACT_CBF_Analysis/${patient_name}/T1w/T1.nii
  
  # After conversion, delete the DICOM images
  rm EXACT_CBF_Analysis/${patient_name}/T1w/*.dcm
  rm EXACT_CBF_Analysis/${patient_name}/ASL/*.dcm
  echo " "
  echo "End of diagnostic message from dcm2niix"
  echo "========================================================================="
  #######################################################################################
  # Step 2: Preprocess the ASL scans
  echo "  - Step 2: ASL scan preprocessing"
  
  # Split the ASL image
  fslsplit EXACT_CBF_Analysis/${patient_name}/ASL/*.nii -t
  
  # Rename the first volume as the PDw image
  echo "       >> Identifying the PDw reference image"
  mv vol0000.nii.gz EXACT_CBF_Analysis/${patient_name}/ASL/PDw.nii.gz
  
  # Delete the 2nd image to leave 7 T-C pairs (MW commented this out since there are 8 pairs for EXV40 onwards)
  # echo "       >> Remove the first volume as it does not have a paired image."
  # rm vol0001.nii.gz
  
  # Merge the rest of the 8 T-C pairs
  echo "       >> Creating T-C pairs timeseries image"
  fslmerge -t EXACT_CBF_Analysis/${patient_name}/ASL/PCASL_timeseries.nii.gz vol*.nii.gz
  
  # Remove all the other temporary files 
  echo "       >> Removing temporary files"
  rm vol*.nii.gz
  
  #######################################################################################
  # Step 3: Anatomical analysis
  # Note: The ASL TC pairs: PCASL_timeseries.nii.gz, PDw: PDw.nii.gz
  echo "  - Step 2: Preprocessing the T1w image for segmentation"
  echo " "
  echo "========================================================================="
  echo "Diagnostic message from fsl_anat"   
  echo " "
  fsl_anat -i EXACT_CBF_Analysis/${patient_name}/T1w/T1.nii -o EXACT_CBF_Analysis/${patient_name}/T1w/FSL_anat_analysis
  
  # Copy the T1w image over:
  cp EXACT_CBF_Analysis/${patient_name}/T1w/FSL_anat_analysis.anat/T1_to_MNI_nonlin.nii.gz EXACT_CBF_Analysis/${patient_name}/T1w/T1_to_std_nonlinear.nii.gz
  
  # Create a QC image for segmentation:
  echo "Creating QC images for segmentation"  
  fsleyes render -of EXACT_CBF_Analysis/0_PNG_Image_QC/${patient_name}_T1_Segmentation_QC.png --scene lightbox --hideCursor EXACT_CBF_Analysis/${patient_name}/T1w/T1_to_std_nonlinear.nii.gz -dr 0 700 -cm greyscale HarvardOxford-cort-maxprob-thr25-2mm.nii.gz -ot label -l harvard-oxford-cortical 
    
  echo " "
  echo "End of diagnostic message from fsl_anat"
  echo "========================================================================="
  
  #######################################################################################
  # Step 3: CBF Analysis
  echo "  - Step 3: Analysing the CBF data"
  echo " "
  echo "========================================================================="
  echo "Diagnostic message from oxford_asl"   
  echo " "
  
  # Estimate the perfusion image using the following parameter inputs:
  # 8 Tag-control pairs, Bolus time = 1.5s, PLD = 1.8s, TR(PDw) = 4.1, T1b = 1.65, label efficiency == 0.85
  oxford_asl -i=EXACT_CBF_Analysis/${patient_name}/ASL/PCASL_timeseries.nii.gz --iaf=tc --ibf=rpt --casl --bolus=1.5 --rpts=8 --tis=3.3 --fslanat=EXACT_CBF_Analysis/${patient_name}/T1w/FSL_anat_analysis.anat -c=EXACT_CBF_Analysis/${patient_name}/ASL/PDw.nii.gz --cmethod=voxel --tr=4.2 --cgain=1 -o=EXACT_CBF_Analysis/${patient_name}/ASL/Oxford_asl_output --bat=1.3 --t1=1.3 --t1b=1.65 --alpha=0.85 --spatial=1 --fixbolus --mc --artoff
  
  echo " "
  echo "End of diagnostic message from oxford_asl"
  echo "========================================================================="
  
  # Create QC for CBF
  echo "       >> Creating QC images for CBF Estimates"
  
  cp EXACT_CBF_Analysis/${patient_name}/ASL/Oxford_asl_output/std_space/perfusion_calib.nii.gz EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz
  
  # QC the voxels with values lower than 20ml/100g/min (blue) vs. higher than that (red)
  fsleyes render -of EXACT_CBF_Analysis/0_PNG_Image_QC/${patient_name}_Low_perfusion_area.png --showColourBar --colourBarSize 50 --scene lightbox --hideCursor EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz -dr 0 40 -cm render3
  
  # QC the CBF map align to the T1w image at the standard space.
  fsleyes render -of EXACT_CBF_Analysis/0_PNG_Image_QC/${patient_name}_CBF_Segmentation_QC.png --showColourBar --colourBarSize 50 --scene lightbox --hideCursor EXACT_CBF_Analysis/${patient_name}/T1w/T1_to_std_nonlinear.nii.gz -dr 0 700 -cm greyscale EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz -dr 0 60 -cm hot
  
  # Segment the CBF image to get mean and median values.
  # Loop through all the ROIs to estimate a mean and median.
  echo "       >> Estimating the ROI CBF value through atlas segmentations."
  
  mkdir EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp
  
  for i in {1..48}; do
      
      uthr=$((i + 2))
      fslmaths HarvardOxford-cort-maxprob-thr25-2mm.nii.gz -thr ${i} -uthr ${uthr} -bin -mul EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp/${i}.nii.gz
  
      mean_value=$(fslstats EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp/${i}.nii.gz -M)
      median_value=$(fslstats EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp/${i}.nii.gz -P 50)
      
      echo "${i},${mean_value}" >> EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex.csv
      echo "${i},${median_value}" >> EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex.csv

  done
  
  
  echo "       >> Generate mean/median estimates and save to the master data sheet."
  
    
  # Cut the index for mean table
  cut -d, -f2- EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex.csv > EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv
    
  # After all the columns have been filled, rotate it so it becomes one row, multiple columns.
  
  awk -F, '{for (i=1; i<=NF; i++) a[NR,i] = $i} 
         NF>p {p = NF} 
         END {for (i=1; i<=p; i++) {for (j=1; j<=NR; j++) printf "%s%s", a[j,i], (j==NR ? "\n" : ",");}}' EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv > EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv
         
  # Add the Participant ID to the first cell and then merge the data to the main data sheet.
  
  awk -v id="$patient_name" 'BEGIN{FS=OFS=","} {print id, $0}' EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv >> EXACT_CBF_Analysis/CBF_ROI_Analysis_Results_Mean.csv
  
     
  # Cut the index for median table
  cut -d, -f2- EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex.csv > EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv 
   
   
  # Same, rotate the columns to rows for the median data sheet
  awk -F, '{for (i=1; i<=NF; i++) a[NR,i] = $i} 
         NF>p {p = NF} 
         END {for (i=1; i<=p; i++) {for (j=1; j<=NR; j++) printf "%s%s", a[j,i], (j==NR ? "\n" : ",");}}' EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv > EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv
  

  # Add the participant ID to the first cell and merge the data to the main data sheet.
  awk -v id="$patient_name" 'BEGIN{FS=OFS=","} {print id, $0}' EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv >> EXACT_CBF_Analysis/CBF_ROI_Analysis_Results_Median.csv
  
  
  # Finally, read the global GM and WM mean perfusion and save it.
  echo "       >> Estimating global GM and WM values."
  mean_gm_perfusion=$(cat EXACT_CBF_Analysis/${patient_name}/ASL/Oxford_asl_output/native_space/perfusion_calib_gm_mean.txt)
  mean_wm_perfusion=$(cat EXACT_CBF_Analysis/${patient_name}/ASL/Oxford_asl_output/native_space/perfusion_calib_wm_mean.txt)
  
  echo "${patient_name},${mean_gm_perfusion},${mean_wm_perfusion}" >> EXACT_CBF_Analysis/CBF_Global_GM_WM_Analysis_Results.csv
  
  # Remove the rotated temporary file to avoid misinterpretation:
  echo "       >> Deleting temporary files"
  rm EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv
  rm EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv
  rm EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv
  rm EXACT_CBF_Analysis/${patient_name}/CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv
  
  # Next, estimate the cortex GM CBF: The next few csv files record the GM CBF in the ROI only.
  
  echo "       >> Preparing GM segmentation"
  # First, BET the T1w image:
  mkdir EXACT_CBF_Analysis/${patient_name}/T1w/FAST
  bet EXACT_CBF_Analysis/${patient_name}/T1w/T1_to_std_nonlinear.nii.gz EXACT_CBF_Analysis/${patient_name}/T1w/FAST/T1_to_std_nonlinear_brain  -f 0.4 -g 0

  # Second, run FAST to create segmentation
  fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -o EXACT_CBF_Analysis/${patient_name}/T1w/FAST/T1_to_std_nonlinear_brain EXACT_CBF_Analysis/${patient_name}/T1w/FAST/T1_to_std_nonlinear_brain
  
  echo "       >> Generating CBF map for only GM"
  # Then, binarize the mask and create a GM segmentation QC image
  fslmaths EXACT_CBF_Analysis/${patient_name}/T1w/FAST/T1_to_std_nonlinear_brain_pve_1.nii.gz -thr 0.25 -bin EXACT_CBF_Analysis/${patient_name}/T1w/GM_Mask.nii.gz
  
  # Mask the CBF Maps
  fslmaths EXACT_CBF_Analysis/${patient_name}/T1w/GM_Mask.nii.gz -mul EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz EXACT_CBF_Analysis/${patient_name}/ASL/GM_CBF_std.nii.gz
  
  # Generate a QC image
  fsleyes render -of EXACT_CBF_Analysis/0_PNG_Image_QC/${patient_name}_GM_CBF_QC.png --scene lightbox --hideCursor EXACT_CBF_Analysis/${patient_name}/T1w/T1_to_std_nonlinear.nii.gz -dr 0 700 -cm greyscale EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Estimate_std.nii.gz -dr 0 60 -cm hot EXACT_CBF_Analysis/${patient_name}/T1w/GM_Mask.nii.gz -cm blue -dr 0 1
  
  # Now analyse the data again, but just the GM CBF.
  mkdir EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp_GM
  
  echo "       >> Segmenting GM for all the cortex ROIs"
  # Loop through all the ROIs:
  for j in {1..48}; do
      
      uthr=$((j + 2))
      fslmaths HarvardOxford-cort-maxprob-thr25-2mm.nii.gz -thr ${j} -uthr ${uthr} -bin -mul EXACT_CBF_Analysis/${patient_name}/ASL/GM_CBF_std.nii.gz EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp_GM/${j}.nii.gz
  
      mean_value=$(fslstats EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp_GM/${j}.nii.gz -M)
      median_value=$(fslstats EXACT_CBF_Analysis/${patient_name}/ASL/CBF_Segmentation_temp_GM/${j}.nii.gz -P 50)
      
      echo "${j},${mean_value}" >> EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex.csv
      echo "${j},${median_value}" >> EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex.csv

  done
  
  echo "       >> Generate mean/median estimates for GM only segmentation and save to the master data sheet."
  # Cut the index for mean table
  cut -d, -f2- EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex.csv > EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv
    
  # After all the columns have been filled, rotate it so it becomes one row, multiple columns.
  
  awk -F, '{for (i=1; i<=NF; i++) a[NR,i] = $i} 
         NF>p {p = NF} 
         END {for (i=1; i<=p; i++) {for (j=1; j<=NR; j++) printf "%s%s", a[j,i], (j==NR ? "\n" : ",");}}' EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv > EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv
         
  # Add the Participant ID to the first cell and then merge the data to the main data sheet.
  
  awk -v id="$patient_name" 'BEGIN{FS=OFS=","} {print id, $0}' EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv >> EXACT_CBF_Analysis/GM_only_CBF_ROI_Analysis_Results_Mean.csv
  
     
  # Cut the index for median table
  cut -d, -f2- EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex.csv > EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv 
   
   
  # Same, rotate the columns to rows for the median data sheet
  awk -F, '{for (i=1; i<=NF; i++) a[NR,i] = $i} 
         NF>p {p = NF} 
         END {for (i=1; i<=p; i++) {for (j=1; j<=NR; j++) printf "%s%s", a[j,i], (j==NR ? "\n" : ",");}}' EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv > EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv
  
  # Add the participant ID to the first cell and merge the data to the main data sheet.
  awk -v id="$patient_name" 'BEGIN{FS=OFS=","} {print id, $0}' EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv >> EXACT_CBF_Analysis/GM_only_CBF_ROI_Analysis_Results_Median.csv
  
  # Remove the rotated temporary file to avoid misinterpretation:
  echo "       >> Deleting temporary files"
  rm EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp.csv
  rm EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp.csv
  rm EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_median_cortex_rotated_temp2.csv
  rm EXACT_CBF_Analysis/${patient_name}/GM_only_CBF_ROI_Analysis_results_mean_cortex_rotated_temp2.csv
  
  # Done!
  echo "#################################################################################"
  echo "Completed analysis for: ${subj}"    
  echo "#################################################################################"
      
done



