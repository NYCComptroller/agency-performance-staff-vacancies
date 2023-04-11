library(plyr)
library(dplyr)
library(zoo)
library(stringi)
library(tidyr)
library(data.table)
library(ggplot2)
library(RSocrata)

rm(list=ls())
options(scipen = 999)
#Reading in key datasets. 1: The PMMR; 2:A scale created separately to normalize partial-year values to a comparable 
#annual figure; 3. The map of MMR Services to Budgetary Units of Appropriation established by the Policy Team;
#4.The vacancy rates by Unit of Appropriation as of October 2022
MMRraw <- read.socrata("https://data.cityofnewyork.us/resource/rbed-zzin.json")
Octoberscale <-read.csv("Processed Data/scale Oct value to full-year value.csv")
UAMap <- read.csv("Raw Data/MMR Service UA Map.csv")
UAVacancies <-read.csv("Raw Data/UA Oct Vacancy.csv")
AgyVacancies <-read.csv("Raw Data/Agy Oct Vacancy.csv")

colnames(Octoberscale) <-c("ID","OctScaleFYV")

UAMap <- UAMap%>%
  filter(!Agency.Number=="#N/A",!Unit.of.Appropriation=="#N/A")%>%
  mutate(UAAgyConcat = paste0(Agency.Number,Unit.of.Appropriation),Concat=paste0(Agency.Full.Name,Raw.Service))

UAVacancies <-UAVacancies%>%
  mutate(UAAgyConcat = paste0(Agency,Unit.of.Appropriation))

#Deduplicating the raw MMR
MMRformatted <- MMRraw[complete.cases(MMRraw[,c("Accepted.Value.YTD")]),] %>%
  distinct()

#Exploring Indicators to get a sense for the shape
MMRIndicators <- MMRformatted[,1:21]%>%
  distinct(ID, .keep_all = TRUE)

MMRIndicators %>%
  group_by(Desired.Direction,Critical)%>%
  count(n())


#Subsetting the MMR to only valid values for October 2022 with an explicit directionality and a defined Service,
#scaling those values to annualized figures where necessary, and measuring whether those with 
#expressed goals are succeeding at those goals.
#NOTE: ~85 Indicators have a Target but no desired direction. They have been excluded.
PMMR22 <- MMRformatted %>%
  filter(Value.Date=="10/01/2022", !Desired.Direction=="None", !Service=="")%>%
  merge(Octoberscale, by="ID", all.x = TRUE)%>%
  mutate(YTDScaled = case_when(!is.na(OctScaleFYV)~Accepted.Value.YTD / OctScaleFYV
                               ,TRUE ~Accepted.Value.YTD))%>%
  mutate(Success = case_when((Desired.Direction=="Up")&(YTDScaled >= Target.MMR) ~ "Met_Goal" 
                             ,(Desired.Direction=="Down")&(YTDScaled <= Target.MMR)~"Met_Goal"
                             ,(Desired.Direction=="Up")&(YTDScaled < Target.MMR) ~ "Did_Not_Meet"
                             ,(Desired.Direction=="Down")&(YTDScaled > Target.MMR)~"Did_Not_Meet")
        )


#In exploring, we determined that the June figures represent the closed fiscal year totals. Filtering values only to 
#a single value for each FY, subsequently merging in October values.
Junes <- MMRformatted%>%
  filter(grepl("06/01",Value.Date),ID %in% PMMRValidValues$ID)%>%
  mutate(OctScaleFYV=NA,
         YTDScaled=Accepted.Value.YTD,
         Success=NA)

PMMRMerge <- rbind(PMMR22,Junes)

#Merging the UAMap into the Annualized PMMR

PMMRMerge <- PMMRMerge %>%
  mutate(Concat=paste0(Agency.Full.Name,Service))%>%
  merge(UAMap,by="Concat", all.x = TRUE)

#Finally! We compare across years. Starting with a Year over Year, Multi Year comparison
PMMRpivot <- PMMRMerge %>%
    distinct()%>%
  pivot_wider(id_cols=c(ID, Desired.Direction,Critical,Agency.Number,UAAgyConcat,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = Fiscal.Year,values_from = YTDScaled)%>%
  merge(PMMR22[,c("ID","Success","Service","Goal","Indicator","Target.MMR","YTDScaled")])%>%
  mutate(Avg3yr = rowMeans(select(.,`2020`,`2021`,`2022`),na.rm=TRUE))%>%
  mutate(Avg5yr = rowMeans(select(.,`2018`,`2019`,`2020`,`2021`,`2022`),na.rm=TRUE))%>%
  mutate(OneYrImproving = case_when((Desired.Direction == "Up")&(`2023`>=`2022`)~"Improving"
                               ,(Desired.Direction == "Up")&(`2023`<`2022`)~"Not_Improving"
                               ,(Desired.Direction == "Down")&(`2023`<=`2022`)~"Improving"
                               ,(Desired.Direction == "Down")&(`2023`>`2022`)~"Not_Improving"))%>%
  mutate(ThreeYrImproving = case_when((Desired.Direction == "Up")&(`2023`>=Avg3yr)~"Improving"
                                      ,(Desired.Direction == "Up")&(`2023`<Avg3yr)~"Not_Improving"
                                      ,(Desired.Direction == "Down")&(`2023`<=Avg3yr)~"Improving"
                                      ,(Desired.Direction == "Down")&(`2023`>Avg3yr)~"Not_Improving"))%>%
  mutate(FiveYrImproving = case_when((Desired.Direction == "Up")&(`2023`>=Avg5yr)~"Improving"
                                      ,(Desired.Direction == "Up")&(`2023`<Avg5yr)~"Not_Improving"
                                      ,(Desired.Direction == "Down")&(`2023`<=Avg5yr)~"Improving"
                                      ,(Desired.Direction == "Down")&(`2023`>Avg5yr)~"Not_Improving"))  

#######################################UA MEASURES OF IMPROVEMENT##########################
CritSuccessUA <- PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = c(Success),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(6:7)),SuccessPct=Met_Goal/Total)

AllSuccessUA <- PMMRpivot %>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = c(Success),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(7:8)),SuccessPct=Met_Goal/Total)

CritOneYrUA <- PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = c(OneYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(6:8)),ImprovePct=Improving/Total)

AllOneYrUA <-PMMRpivot %>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = OneYrImproving,values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(6:8)),ImprovePct=Improving/Total)

CritFiveYearUA <-PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = c(FiveYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(6:8)),ImprovePct=Improving/Total)

AllFiveYearUA <-PMMRpivot %>%
  pivot_wider(id_cols=c(UAAgyConcat,Agency.Number,Agency.Full.Name.y,Unit.of.Appropriation,U.A.Name)
              ,names_from = c(FiveYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(UAVacancies[,c("UAAgyConcat","November.Plan","October.Actuals","Vacancy.Rate")],by="UAAgyConcat",
        all.x=TRUE)%>%
  mutate(Total=rowSums(across(6:8)),ImprovePct=Improving/Total)

CritCombined <- CritSuccessUA %>%
  merge(CritOneYrUA[,c("UAAgyConcat","Improving","Not_Improving","NA","Total","ImprovePct")],by="UAAgyConcat",
        all.x = TRUE,suffixes=c(".s",".one"))%>%
  merge(CritFiveYearUA[,c("UAAgyConcat","Improving","Not_Improving","NA","Total","ImprovePct")],by="UAAgyConcat",
        all.x=TRUE,suffixes=c("",".five"))

AllCombined <-AllSuccessUA %>%
  merge(AllOneYrUA[,c("UAAgyConcat","Improving","Not_Improving","NA","Total","ImprovePct")],by="UAAgyConcat",
        all.x = TRUE,suffixes=c(".s",".one"))%>%
  merge(AllFiveYearUA[,c("UAAgyConcat","Improving","Not_Improving","NA","Total","ImprovePct")],by="UAAgyConcat",
        all.x=TRUE,suffixes=c("",".five"))

######################AGENCY MEASURES OF IMPROVEMENT##################################
CritSuccessAgy <- PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(Success),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(2:3)),SuccessPct=Met_Goal/Total)

AllSuccessAgy <- PMMRpivot %>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(Success),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(3:4)),SuccessPct=Met_Goal/Total)

CritOneYrAgy <- PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(OneYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(2:4)),ImprovePct=Improving/Total)

AllOneYrAgy <- PMMRpivot %>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(OneYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(2:4)),ImprovePct=Improving/Total)

CritFiveYearAgy <-PMMRpivot %>%
  filter(Critical=="Yes")%>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(FiveYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(2:4)),ImprovePct=Improving/Total)

AllFiveYrAgy <- PMMRpivot %>%
  pivot_wider(id_cols=c(Agency.Number)
              ,names_from = c(FiveYrImproving),values_from = ID, values_fn = list(ID=length)
              ,values_fill=0)%>%
  merge(AgyVacancies[,c("Agency","Agency.Name","November.Plan","October.Actuals","Vacancy.Rate")],by.x="Agency.Number",
        by.y="Agency",all.x=TRUE)%>%
  mutate(Total=rowSums(across(2:4)),ImprovePct=Improving/Total)

CritAgyCombined <- CritSuccessAgy %>%
  merge(CritOneYrAgy[,c("Agency.Number","Improving","Not_Improving","NA","Total","ImprovePct")],by="Agency.Number",
        all.x = TRUE,suffixes=c(".s",".one"))%>%
  merge(CritFiveYearAgy[,c("Agency.Number","Improving","Not_Improving","NA","Total","ImprovePct")],by="Agency.Number",
        all.x=TRUE,suffixes=c("",".five"))

AllAgyCombined <- AllSuccessAgy %>%
  merge(AllOneYrAgy[,c("Agency.Number","Improving","Not_Improving","NA","Total","ImprovePct")],by="Agency.Number",
        all.x = TRUE,suffixes=c(".s",".one"))%>%
  merge(AllFiveYrAgy[,c("Agency.Number","Improving","Not_Improving","NA","Total","ImprovePct")],by="Agency.Number",
        all.x=TRUE,suffixes=c("",".five"))


write.csv(AllCombined, "Final Data/All Indicators UA Outcomes.csv")
write.csv(CritCombined, "Final Data/Critical Indicators UA Outcomes.csv")
write.csv(AllAgyCombined, "Final Data/All Indicators Agency Outcomes.csv")
write.csv(CritAgyCombined, "Final Data/Critical Indicators Agency Outcomes.csv")
write.csv(PMMRpivot, "Final Data/Tidy Indicator Level Data.csv")
