# Library import
library(tidyverse)
library(lubridate)
library(highcharter)
library(plotly)
library(cluster)
library(factoextra)

# Data import
df_data <- read.csv("data.csv")
glimpse(df_data)

# Data cleansing
df_data <- df_data %>% 
  mutate(Quantity = replace(Quantity, Quantity<=0, NA),
         UnitPrice = replace(UnitPrice, UnitPrice<=0, NA))
df_data <- df_data %>%
  drop_na()
glimpse(df_data)

# RFM Analysis
df_data <- df_data %>% 
  mutate(InvoiceNo=as.factor(InvoiceNo), StockCode=as.factor(StockCode), 
         InvoiceDate=as.Date(InvoiceDate, '%m/%d/%Y %H:%M'), CustomerID=as.factor(CustomerID), 
         Country=as.factor(Country))

df_data$total_dolar = df_data$Quantity * df_data$UnitPrice

df_data$days <- weekdays(df_data$InvoiceDate)
df_data$days <- as.factor(df_data$days)

df_data$mday <- mday(as.POSIXlt(df_data$InvoiceDate))

glimpse(df_data)

## Total customer per month
customer <- df_data %>%
  group_by(InvoiceDate) %>%
  summarise(total_customer = n_distinct(CustomerID))

customer$month <- floor_date(customer$InvoiceDate, "month")

customer <- customer %>%
  group_by(month) %>%
  summarize(total_customer = sum(total_customer)) %>%
  filter(month != "2011-12-01") 

hc <- customer %>% hchart(
  'line', hcaes(x = month, y = total_customer),
  color = "steelblue"
  ) %>% 
  hc_title(text="Total Customer per Month") 

hc

## Total transaction per month
transaction <- df_data %>%
  group_by(InvoiceDate) %>%
  summarise(total_transaction = n_distinct(InvoiceNo))

transaction$month <- floor_date(transaction$InvoiceDate, "month")

transaction <- transaction %>%
  group_by(month) %>%
  summarize(total_transaction = sum(total_transaction)) %>%
  filter(month != "2011-12-01") 

ht <- transaction %>% hchart(
  'line', hcaes(x = month, y = total_transaction),
  color = "steelblue"
  ) %>% 
  hc_title(text="Total Transaction per Month") 

ht

## Total sales per month
sales <- df_data %>%
  mutate(total_dolar) %>%
  group_by(InvoiceDate) %>%
  summarise(total_sales = sum(total_dolar))

sales$month <- floor_date(sales$InvoiceDate, "month")

sales <- sales %>%
  group_by(month) %>%
  summarize(total_sales = sum(total_sales)) %>%
  filter(month != "2011-12-01") 

hs <- sales %>% hchart(
  'line', hcaes(x = month, y = total_sales),
  color = "steelblue"
  ) %>% 
  hc_title(text="Total Sales per Month") 

hs

## Classify new & returning cust
sales_data <- df_data %>%
  group_by(CustomerID)%>%
  mutate(date_of_first_engagement=min(InvoiceDate))%>% #customer first order
  ungroup()

sales_data <- sales_data%>%
  mutate(Customer_Status = case_when(InvoiceDate>date_of_first_engagement ~ "Returning",
                                     InvoiceDate == date_of_first_engagement ~ "New",
                                     TRUE ~ "Other"))

New_and_Returning_Customers <-  sales_data%>%
  group_by(floor_date(InvoiceDate,unit = 'month'))%>%
  summarise(New_Customers = n_distinct(CustomerID[Customer_Status=="New"]),
            Returning_Customers= n_distinct(CustomerID[Customer_Status=="Returning"]))

colnames(New_and_Returning_Customers) <- c("Date", "New_Cus", "Return_Cus")
New_and_Returning_Customers

## Determine mean sales by month
New_and_Returning_Customers %>% 
  filter(Date != "2011-12-01") %>% hchart(
  'line', hcaes(x = Date, y = New_Cus),
  color = "steelblue"
  ) %>% 
  hc_title(text="Mean Sales per Month of New Customers") 

New_and_Returning_Customers %>% 
  filter(Date != "2011-12-01") %>% hchart(
  'line', hcaes(x = Date, y = Return_Cus),
  color = "steelblue"
  ) %>% 
  hc_title(text="Mean Sales per Month of Returning Customers") 

# Create RFM data
df_RFM <- df_data %>% 
  group_by(CustomerID) %>% 
  summarise(recency=as.numeric(as.Date("2012-01-01")-max(InvoiceDate)),
            frequency=n_distinct(InvoiceNo),
            monitery= sum(total_dolar)/n_distinct(InvoiceNo))

summary(df_RFM)

# Recency segmentation
hchart(hist(
    df_RFM$recency, breaks = 396, plot=FALSE), type = 'histogram', name = 'Recency Counts',
       color = '#669900') %>% 
  hc_title(text="Recency Segmentation") 

df_RFM$frequency_standard <- scale(df_RFM$frequency)
summary(scale(df_RFM$frequency))

df_RFM$monitery_standard <- scale(df_RFM$monitery)
summary(scale(df_RFM$monitery))

## Determine optimal number of clusters
set.seed(1)
fviz_nbclust(df_RFM[c("frequency_standard", "monitery_standard")], kmeans, method = "wss")

segmentasi <- kmeans(x=df_RFM[c("frequency_standard", "monitery_standard")], 
                     centers=4, nstart=25)
summary(segmentasi$centers)

df_RFM$cluster <- segmentasi$cluster

df_RFM %>%
  group_by(cluster) %>%
  summarise(mean_freq = mean(frequency),
            mean_monitery = mean(monitery))

# pair it up within the particular value
# cluster mean_freq mean_monitery
# *   <int>     <dbl>         <dbl>
# 1       1      1.5         80710. special
# 2       2      2.85          369. low
# 3       3     18.7           529. medium
# 4       4    122.            823. high

df_RFM <- df_RFM%>%
  mutate(segmentation = case_when(cluster == 1 ~ "Low Value",
                                  cluster == 2 ~ "Medium Value",
                                  cluster == 3 ~ "Special Value",
                                  cluster == 4 ~ "High Value",
                                  TRUE ~ "Other"))

ggplot(df_RFM, aes(frequency, monitery, color=factor(segmentation))) +
  geom_point() +
  labs(title = "Customer Value Segmentation",
       color = "Segmentation") 

## Compile all assets
Segmen.Pelanggan <- data.frame(cluster=c(1,2,3,4), 
                               Value.Segment=c("Low Value", "Medium Value",
                                             "Specia; Value", "High Value"))

Identitas.Cluster <- list(Segmentasi=segmentasi, 
                          Segmen.Pelanggan=Segmen.Pelanggan, 
                          column=c("frequency_standard", "monitery_standard"))
saveRDS(Identitas.Cluster,"cluster_rfm.rds")
glimpse(Identitas.Cluster)

## Total Customer per Segment
customer_segment <-df_RFM %>% 
  group_by(segmentation) %>% 
  summarise(freq=n_distinct(CustomerID))

customer_segment <- customer_segment %>%
  group_by(segmentation) %>%
  mutate(percen = freq/sum(customer_segment$freq))

customer_segment %>%
  ggplot(aes(segmentation, percen, fill=segmentation)) +
  geom_bar(stat = "identity")

## Total monatory per recency
df_RFM <- df_RFM%>%
  mutate(recency_segment = case_when(recency <= 30 ~ "Active",
                                  recency <= 90 ~ "Warm",
                                  recency <= 180 ~ "Cold",
                                  recency >= 180 ~ "Inactive",
                                  TRUE ~ "Other"))

df_RFM %>%
  group_by(recency_segment) %>%
  summarise(monatory_segment = sum(monitery)) %>%
  mutate(percen = monatory_segment/sum(monatory_segment) *100) %>%
  ggplot(aes(recency_segment, percen, fill=recency_segment)) +
  geom_bar(stat = "identity")

## Total monatory per segment
df_RFM %>%
  group_by(segmentation) %>%
  summarise(monatory_segment = sum(monitery)) %>%
  mutate(percen = monatory_segment/sum(monatory_segment) *100) %>%
  ggplot(aes(segmentation, percen, fill=segmentation)) +
  geom_bar(stat = "identity")

## cross value recency segment & cust segmentation
table(df_RFM$recency_segment, df_RFM$segmentation)

final_data <- inner_join(df_data, df_RFM, by="CustomerID")

sum_customer <- length(unique(final_data$CustomerID))
sum_monetery <- sum(final_data$total_dolar)

# Behavioral analysis
## weekly
final_data$month <- months(final_data$InvoiceDate)

high_active_cust <- final_data %>%
  filter(segmentation == "High Value",
         recency_segment == "Active") 

days <-
  plyr::count(high_active_cust$days)
colnames(days) <- c("days", "freq")

days_cus <- data.frame(
  days = factor(c("Monday", "Tuesday", "Wednesday",
                  "Thursday", "Friday", "Saturday", "Sunday"),
                levels = c("Monday", "Tuesday", "Wednesday",
                           "Thursday", "Friday", "Saturday", "Sunday")))


data_df <- left_join(days_cus, days, by="days")
ggplot(data_df, aes(days, freq, fill=days)) +
  geom_bar(stat = "identity") +
  coord_polar()

## monthly
input_recency <- c("Active", "Warm", "Cold")
input_value <- c("Low Value", "Medium Value")

summary_customer <- final_data %>%
  filter(recency_segment %in% input_recency,
         segmentation %in% input_value)

date_day <-
  plyr::count(summary_customer$mday)
colnames(date_day) <- c("date", "freq")
date_day

date_cus <- data.frame(
  date = c(1:31))

date_order_individu <- left_join(date_cus, date_day, by="date")
ggplot(date_order_individu, aes(factor(date), freq, fill=freq)) +
  geom_bar(stat = "identity") +
  coord_polar() +
  theme_minimal() +
  labs(title = "Monthly Order Habit") +
  theme(
    legend.position = "none",
    axis.title = element_blank(),
    axis.text.y = element_blank(),
    panel.grid.minor = element_blank()
  )

## annual
date_month <- plyr::count(summary_customer$month)
colnames(date_month) <- c("month", "freq")

month_year <- data.frame(
  month = factor(c(unique(final_data$month)),
                 levels = c("January", "February", "March", "April",    
                            "May", "June", "July", "August", "September",
                            "October", "November", "December"))
)


monthly_order_individu <- left_join(month_year, date_month, by="month")
monthly_order_individu$month <- factor(monthly_order_individu$month,
                                       levels = c("January", "February", "March", "April",    
                                                  "May", "June", "July", "August", "September",
                                                  "October", "November", "December"))
ggplot(monthly_order_individu, aes(month, freq, fill=freq)) +
  geom_bar(stat = "identity") +
  coord_polar() +
  theme_minimal() +
  labs(title = "Annual Order Habbit") +
  theme(
    legend.position = "none",
    axis.title = element_blank(),
    axis.text.y = element_blank(),
    panel.grid.minor = element_blank()
  )