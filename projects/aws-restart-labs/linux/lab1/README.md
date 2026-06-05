# Linux Lab 1: Introduction to an Amazon Linux Amazon Machine Image (AMI)

Introduction to an Amazon Linux Amazon Machine Image (AMI)
This lab is designed to reinforce your knowledge of the basic command line interface functionality and provide a solid foundation from which you can continue to learn about new commands and capabilities within the Linux shell.

 

Duration
This lab requires approximately 30 minutes to complete.

 

AWS service restrictions
In this lab environment, access to AWS services and service actions might be restricted to the ones that you need to complete the lab instructions. You might encounter errors if you attempt to access other services or perform actions beyond the ones that this lab describes.

 

Scenario
In this lab, you use Secure Shell (SSH) to access an Amazon Linux Amazon Machine Image (AMI) within Vocareum labs. Next, you use the man command to access the man pages.

Objectives
After completing this lab, you will be able to:

Use SSH to access an Amazon Linux AMI within Vocareum labs
Understand the purpose of the man command
Demonstrate the search feature of the man pages
Examine man page headers
The following components are created for you as a part of the lab environment:

Amazon EC2 - Command Host (in the public subnet): You log in to this instance to use the commands listed within this lab.
The following are other components in this lab. You examine these components later during this course.

Public subnet
Amazon Virtual Private Cloud (Amazon VPC)
 

Accessing the AWS Management Console
At the top of these instructions, choose Start Lab to launch your lab.
A Start Lab panel opens, and it displays the lab status.

Tip: If you need more time to complete the lab, choose the Start Lab button again to restart the timer for the environment.

Wait until you see the message Lab status: ready, then close the Start Lab panel by choosing the X.

At the top of these instructions, choose AWS.
This opens the AWS Management Console in a new browser tab. The system will automatically log you in.

Tip: If a new browser tab does not open, a banner or icon is usually at the top of your browser with a message that your browser is preventing the site from opening pop-up windows. Choose the banner or icon and then choose Allow pop ups.

Arrange the AWS Management Console tab so that it displays along side these instructions. Ideally, you will be able to see both browser tabs at the same time so that you can follow the lab steps more easily.

 

Task 1: Use SSH to connect to an Amazon Linux EC2 instance
In this task, you will connect to a Amazon Linux EC2 instance. You will use an SSH utility to perform all of these operations. The following instructions vary slightly depending on whether you are using Windows or Mac/Linux.

 Windows Users: Using SSH to Connect
 These instructions are specifically for Windows users. If you are using macOS or Linux, skip to the next section.

Select the Details drop-down menu above these instructions you are currently reading, and then select Show. A Credentials window will be presented.

Select the Download PPK button and save the labsuser.ppk file.
Typically your browser will save it to the Downloads directory.

Make a note of the PublicIP address.

Then exit the Details panel by selecting the X.

Download  PuTTY to SSH into the Amazon EC2 instance. If you do not have PuTTY installed on your computer, download it here.

Open putty.exe

Configure your PuTTY session by following the directions in the following link: Connect to your Linux instance using PuTTY

Windows Users: Select here to skip ahead to the next task.


 

macOS  and Linux  Users
These instructions are specifically for Mac/Linux users. If you are a Windows user, skip ahead to the next task.

Select the Details drop-down menu above these instructions you are currently reading, and then select Show. A Credentials window will be presented.

Select the Download PEM button and save the labsuser.pem file.

Make a note of the PublicIP address.

Then exit the Details panel by selecting the X.

Open a terminal window, and change directory cd to the directory where the labsuser.pem file was downloaded. For example, if the labuser.pem file was saved to your Downloads directory, run this command:

cd ~/Downloads
Change the permissions on the key to be read-only, by running this command:

chmod 400 labsuser.pem
Run the below command (replace <public-ip> with the PublicIP address you copied earlier).
Alternatively, return to the EC2 Console and select Instances. Check the box next to the instance you want to connect to and in the Description tab copy the IPv4 Public IP value.:

ssh -i labsuser.pem ec2-user@<public-ip>
Type yes when prompted to allow the first connection to this remote SSH server.
Because you are using a key pair for authentication, you will not be prompted for a password.


Task 2: Exercise - Explore the Linux man pages
In this exercise, you use a bash terminal to view the Linux standard help system. This system is generally referred to as the manual pages (or man pages).

To open the manual pages for the man program, enter the following command in the PuTTY terminal window, and press Enter:

man man
The terminal window at the command prompt, displays the result of the man man command. 

Figure: At the command prompt the man man command has been entered.

 

To identify the major sections of the man pages, look for the headers in the terminal (as the following figure shows).

Note: You can move in the man pages by pressing the up and down arrow keys.

The following are a few important man page headers. (This list is not all inclusive.):

NAME
SYNOPSIS
DESCRIPTION
OVERVIEW
EXAMPLES
FILES
OPTIONS
SEE ALSO
![The terminal window displaying the man page utilities or man page.](images/man_command_synopsis.png)

*Figure: The man page displays important information about a command.* 
Take note of the DESCRIPTION header, particularly the section numbers.
![The terminal window at the command prompt displaying the DESCRIPTION header. The DESCRIPTION header provides an overview of a command.](_images/man_command_description.png_)

*The DESCRIPTION header provides an overview of a command.*
To exit the man pages, enter q
